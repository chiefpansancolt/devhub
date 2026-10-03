import Foundation
import Testing
@testable import DevHubCore

private func node(_ version: String, _ manager: RuntimeManager = .nvm) -> RuntimeVersion {
    RuntimeVersion(bucket: .node, version: version, manager: manager)
}

private func ruby(_ version: String, _ manager: RuntimeManager = .rbenv) -> RuntimeVersion {
    RuntimeVersion(bucket: .ruby, version: version, manager: manager)
}

@Suite struct RuntimeReleaseParserTests {
    @Test func theNodeListLosesTheLeadingV() throws {
        let versions = try RuntimeReleaseParser.parseNode(Fixture.data("node-dist-index.json"))

        #expect(versions.first == "26.10.0")
        #expect(versions.contains("24.18.1"))
        #expect(versions.allSatisfy { !$0.hasPrefix("v") })
        #expect(versions.count == 16)
    }

    @Test func aNodeListThatIsNotJSONIsRejected() {
        #expect(throws: RuntimeReleaseError.unreadable) { try RuntimeReleaseParser.parseNode(Data("<html>".utf8)) }
    }

    @Test func theRubyListHoldsEachReleaseOnce() throws {
        let versions = try RuntimeReleaseParser.parseRuby(Fixture.data("ruby-index.txt"))

        #expect(Set(versions).count == versions.count)
        #expect(versions.contains("4.0.7"))
        #expect(versions.contains("3.4.10"))
    }

    @Test func rubyPreviewsCandidatesAndPatchLevelsAreSkipped() throws {
        let versions = try RuntimeReleaseParser.parseRuby(Fixture.data("ruby-index.txt"))

        #expect(!versions.contains { $0.contains("preview") || $0.contains("rc") || $0.contains("p374") })
        #expect(versions.allSatisfy { $0.allSatisfy { $0.isNumber || $0 == "." } })
    }

    @Test func aRubyListWithoutTheHeaderIsRejected() {
        #expect(throws: RuntimeReleaseError.unreadable) { try RuntimeReleaseParser.parseRuby(Data("ruby-3.4.1\thttps://x".utf8)) }
    }

    @Test func theOfficialSourceReadsTheListOfTheTool() async throws {
        let source = OfficialRuntimeReleases { url in
            url.host == "nodejs.org" ? try Fixture.data("node-dist-index.json") : try Fixture.data("ruby-index.txt")
        }

        #expect(try await source.releases(for: .node).first == "26.10.0")
        #expect(try await source.releases(for: .ruby).contains("4.0.7"))
        #expect(try await source.releases(for: .rust).isEmpty)
    }
}

@Suite struct RuntimeVersionShapeTests {
    @Test func onlyDottedNumbersOfTwoToFourPartsArePlainVersions() {
        for text in ["26.10.0", "3.4", "4.0.7", "1.2.3.4"] {
            #expect(RuntimeReleaseParser.isPlainVersion(text), "\(text)")
        }
        for text in ["26", "", "1.2.3.4.5", "1..2", "1.2.x", "1.2.3-rc1", "v1.2.3", "1.2.3; ls", "١.٢.٣"] {
            #expect(!RuntimeReleaseParser.isPlainVersion(text), "\(text)")
        }
    }
}

@Suite struct RuntimeUpdatePlannerTests {
    private func offers(
        _ bucket: Bucket = .node,
        installed: [RuntimeVersion],
        releases: [String],
        dismissed: Set<String> = []
    ) -> [RuntimeOffer] {
        RuntimeUpdatePlanner.offers(bucket: bucket, installed: installed, releases: releases, dismissed: dismissed)
    }

    private let nodeReleases = ["26.10.0", "26.9.0", "25.9.0", "24.21.0", "24.20.0", "22.23.3", "22.23.2", "20.20.2"]

    @Test func aNewerMajorVersionIsOffered() {
        let result = offers(installed: [node("24.21.0")], releases: nodeReleases)

        #expect(result.count == 1)
        #expect(result[0].version == "26.10.0")
        #expect(result[0].installedVersion == "24.21.0")
        #expect(result[0].manager == .nvm)
    }

    @Test func aNewerPatchOfAnOlderLineIsOffered() {
        let result = offers(installed: [node("26.10.0"), node("22.23.1")], releases: nodeReleases)

        #expect(result.map(\.version) == ["22.23.3"])
        #expect(result[0].installedVersion == "22.23.1")
    }

    @Test func theNewestOverallAndTheNewestOfEachInstalledLineAreAllOffered() {
        let result = offers(installed: [node("24.20.0"), node("22.23.1")], releases: nodeReleases)

        #expect(result.map(\.version) == ["26.10.0", "24.21.0", "22.23.3"])
    }

    @Test func aLineThatIsNotInstalledIsNotOfferedUnlessItIsTheNewest() {
        let result = offers(installed: [node("24.21.0")], releases: nodeReleases)

        #expect(!result.map(\.version).contains("22.23.3"))
        #expect(!result.map(\.version).contains("25.9.0"))
    }

    @Test func theNewestReleaseOfTheNewestInstalledLineIsOfferedOnce() {
        let result = offers(installed: [node("26.9.0")], releases: nodeReleases)

        #expect(result.map(\.version) == ["26.10.0"])
    }

    @Test func nothingIsOfferedWhenTheNewestIsInstalled() {
        #expect(offers(installed: [node("26.10.0"), node("24.21.0"), node("22.23.3")], releases: nodeReleases).isEmpty)
    }

    @Test func anOlderReleaseThanTheInstalledOneIsNeverOffered() {
        #expect(offers(installed: [node("24.21.0")], releases: ["24.20.0", "24.19.0"]).isEmpty)
    }

    @Test func aDismissedVersionIsNotOfferedAgain() {
        let result = offers(installed: [node("24.21.0")], releases: nodeReleases, dismissed: ["runtime/node/26.10.0"])

        #expect(result.isEmpty)
    }

    @Test func aDismissedReleaseDoesNotHideTheNextOne() {
        let result = offers(installed: [node("24.21.0")], releases: ["26.11.0"] + nodeReleases, dismissed: ["runtime/node/26.10.0"])

        #expect(result.map(\.version) == ["26.11.0"])
    }

    @Test func aStandardPackagesDismissalDoesNotHideARuntimeOffer() {
        let result = offers(installed: [node("24.21.0")], releases: nodeReleases, dismissed: ["node/26.10.0"])

        #expect(result.map(\.version) == ["26.10.0"])
    }

    @Test func versionsThatAreComparedByNumberAndNotByText() {
        let result = offers(.ruby, installed: [ruby("3.4.9")], releases: ["3.4.10", "3.4.2"])

        #expect(result.map(\.version) == ["3.4.10"])
    }

    @Test func aRubyLineIsMajorAndMinor() {
        let result = offers(.ruby, installed: [ruby("3.4.1"), ruby("3.3.5")], releases: ["4.0.7", "3.4.11", "3.3.12", "3.2.11"])

        #expect(result.map(\.version) == ["4.0.7", "3.4.11", "3.3.12"])
    }

    @Test func versionsOfTheOtherToolDoNotCount() {
        #expect(offers(.node, installed: [ruby("3.4.1")], releases: nodeReleases).isEmpty)
        #expect(offers(.ruby, installed: [node("26.10.0")], releases: ["4.0.7"]).isEmpty)
    }

    @Test func versionsThatAManagerCannotInstallAreIgnored() {
        #expect(offers(installed: [node("24.21.0", .custom)], releases: nodeReleases).isEmpty)
        #expect(offers(.ruby, installed: [ruby("3.4.1", .chruby)], releases: ["4.0.7"]).isEmpty)
    }

    @Test func aManagerThatCannotInstallDoesNotHideTheOnesThatCan() {
        let result = offers(installed: [node("25.0.0", .custom), node("24.20.0", .fnm)], releases: nodeReleases)

        #expect(result.map(\.version) == ["26.10.0", "24.21.0"])
        #expect(result.allSatisfy { $0.manager == .fnm })
    }

    @Test func aVersionInstalledByAnotherManagerIsNotOffered() {
        #expect(offers(installed: [node("24.21.0"), node("26.10.0", .volta)], releases: nodeReleases).isEmpty)
    }

    @Test func aVersionInAFolderThatNoManagerOwnsIsNotOfferedAgain() {
        let result = offers(installed: [node("24.21.0"), node("26.10.0", .custom)], releases: nodeReleases)

        #expect(result.isEmpty)
    }

    @Test func theManagerOfTheLineThatWillBeReplacedIsUsed() {
        let result = offers(installed: [node("24.20.0", .fnm), node("22.23.1", .asdf)], releases: nodeReleases)

        #expect(result.first { $0.version == "22.23.3" }?.manager == .asdf)
        #expect(result.first { $0.version == "24.21.0" }?.manager == .fnm)
    }

    @Test func prereleasesAndNonNumericVersionsAreIgnored() {
        let result = offers(installed: [node("24.21.0"), node("lts")], releases: ["27.0.0-rc.1", "27.0.0-nightly", "24.21.0"])

        #expect(result.isEmpty)
    }

    @Test func noInstalledVersionMeansNoOffer() {
        #expect(offers(installed: [], releases: nodeReleases).isEmpty)
    }

    @Test func theRealReleaseListsOfferTheNewestForAnOldInstall() throws {
        let releases = try RuntimeReleaseParser.parseNode(Fixture.data("node-dist-index.json"))

        let result = offers(installed: [node("24.18.0"), node("18.20.4")], releases: releases)

        #expect(result.map(\.version) == ["26.10.0", "24.21.0", "18.20.8"])
    }
}

@Suite struct RuntimeInstallerTests {
    private let home = URL(filePath: "/Users/example")

    private func command(_ bucket: Bucket, _ manager: RuntimeManager, _ version: String = "26.10.0", asDefault: Bool, kind: PackageKind? = nil) -> ToolCommand? {
        let package = InstalledPackage(
            bucket: bucket, kind: kind ?? (asDefault ? .runtimeAsDefault : .runtime), name: bucket.rawValue, group: manager.rawValue,
            installedVersion: "", availableUpdate: version
        )
        return RuntimeInstaller(home: home).command(for: package)
    }

    private func script(_ bucket: Bucket, _ manager: RuntimeManager, _ version: String = "26.10.0", asDefault: Bool) -> String? {
        command(bucket, manager, version, asDefault: asDefault)?.arguments.last
    }

    @Test func nvmLoadsItsScriptBecauseNvmIsAShellFunction() {
        #expect(script(.node, .nvm, asDefault: true) == ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0 && nvm alias default 26.10.0")
        #expect(script(.node, .nvm, asDefault: false) == ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0")
    }

    @Test func fnmInstallsAndSetsTheDefault() {
        #expect(script(.node, .fnm, asDefault: true) == "fnm install 26.10.0 && fnm default 26.10.0")
        #expect(script(.node, .fnm, asDefault: false) == "fnm install 26.10.0")
    }

    @Test func voltaOnlyFetchesAVersionThatMustNotBecomeTheDefault() {
        #expect(script(.node, .volta, asDefault: true) == "volta install node@26.10.0")
        #expect(script(.node, .volta, asDefault: false) == "volta fetch node@26.10.0")
    }

    @Test func asdfTriesTheNewSetCommandBeforeTheOldGlobalOne() {
        #expect(script(.node, .asdf, asDefault: true) == "asdf install nodejs 26.10.0 && { asdf set --home nodejs 26.10.0 || asdf global nodejs 26.10.0; }")
        #expect(script(.ruby, .asdf, "4.0.7", asDefault: false) == "asdf install ruby 4.0.7")
    }

    @Test func rubyManagersInstallAndSetTheDefault() {
        #expect(script(.ruby, .rbenv, "4.0.7", asDefault: true) == "rbenv install 4.0.7 && rbenv global 4.0.7")
        #expect(script(.ruby, .rbenv, "3.4.11", asDefault: false) == "rbenv install 3.4.11")
        #expect(script(.ruby, .rvm, "4.0.7", asDefault: true) == ". \"$HOME/.rvm/scripts/rvm\" && rvm install 4.0.7 --default")
        #expect(script(.ruby, .rvm, "3.4.11", asDefault: false) == ". \"$HOME/.rvm/scripts/rvm\" && rvm install 3.4.11")
    }

    @Test func aManagerThatDoesNotFitTheToolHasNoCommand() {
        #expect(script(.node, .rbenv, asDefault: true) == nil)
        #expect(script(.ruby, .nvm, "4.0.7", asDefault: true) == nil)
        #expect(script(.ruby, .volta, "4.0.7", asDefault: true) == nil)
    }

    @Test func chrubyAndCustomFoldersHaveNoCommand() {
        #expect(script(.ruby, .chruby, "4.0.7", asDefault: true) == nil)
        #expect(script(.node, .custom, asDefault: true) == nil)
    }

    @Test func aVersionThatCouldRunShellCodeIsRefused() {
        #expect(command(.node, .nvm, "26.10.0; touch /tmp/x", asDefault: true) == nil)
        #expect(command(.node, .nvm, "$(whoami)", asDefault: true) == nil)
        #expect(command(.node, .nvm, "", asDefault: true) == nil)
        #expect(command(.node, .nvm, "latest", asDefault: true) == nil)
    }

    @Test func anotherKindOfPackageIsNotAnInstallOfAVersion() {
        #expect(command(.node, .nvm, asDefault: true, kind: .npmGlobal) == nil)
    }

    @Test func aPackageWithoutAVersionHasNoCommand() {
        let package = InstalledPackage(bucket: .node, kind: .runtime, name: "node", group: "nvm", installedVersion: "")

        #expect(RuntimeInstaller(home: home).command(for: package) == nil)
    }

    @Test func theCommandRunsInBashWithTheManagerFoldersOnThePath() throws {
        let command = try #require(command(.node, .nvm, asDefault: true))

        #expect(command.executable.path == "/bin/bash")
        #expect(command.arguments.first == "-c")
        #expect(command.environment["NVM_DIR"] == "/Users/example/.nvm")
        #expect(command.environment["HOME"] == "/Users/example")
        let path = try #require(command.environment["PATH"])
        #expect(path.contains("/Users/example/.volta/bin"))
        #expect(path.contains("/Users/example/.rbenv/shims"))
        #expect(path.contains("/opt/homebrew/bin"))
    }

    @Test func theNodeAndRubyScannersBuildTheSameCommand() {
        let package = InstalledPackage(bucket: .node, kind: .runtimeAsDefault, name: "node", group: "fnm", installedVersion: "", availableUpdate: "26.10.0")
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let nodeScanner = NodeScanner(installations: [], runner: runner)
        let rubyScanner = RubyScanner(installations: [], runner: runner)

        #expect(nodeScanner.installCommand(for: package)?.arguments.last == "fnm install 26.10.0 && fnm default 26.10.0")
        let rubyPackage = InstalledPackage(bucket: .ruby, kind: .runtime, name: "ruby", group: "rbenv", installedVersion: "", availableUpdate: "3.4.11")
        #expect(rubyScanner.installCommand(for: rubyPackage)?.arguments.last == "rbenv install 3.4.11")
    }
}

@Suite struct RuntimeUninstallCommandTests {
    private let home = URL(filePath: "/Users/example")

    private func script(_ bucket: Bucket, _ manager: RuntimeManager, _ version: String = "24.20.0", kind: PackageKind = .runtime) -> String? {
        let package = InstalledPackage(bucket: bucket, kind: kind, name: bucket.rawValue, group: manager.rawValue, installedVersion: version)
        return RuntimeInstaller(home: home).uninstallCommand(for: package)?.arguments.last
    }

    @Test func eachManagerRemovesTheVersionWithItsOwnCommand() {
        #expect(script(.node, .nvm) == ". \"$NVM_DIR/nvm.sh\" --no-use && nvm uninstall 24.20.0")
        #expect(script(.node, .fnm) == "fnm uninstall 24.20.0")
        #expect(script(.node, .asdf) == "asdf uninstall nodejs 24.20.0")
        #expect(script(.ruby, .rbenv, "3.4.1") == "rbenv uninstall -f 3.4.1")
        #expect(script(.ruby, .rvm, "3.4.1") == ". \"$HOME/.rvm/scripts/rvm\" && rvm uninstall 3.4.1")
        #expect(script(.ruby, .asdf, "3.4.1") == "asdf uninstall ruby 3.4.1")
    }

    @Test func voltaChrubyAndCustomFoldersCannotUninstallAVersion() {
        #expect(script(.node, .volta) == nil)
        #expect(script(.ruby, .chruby, "3.4.1") == nil)
        #expect(script(.node, .custom) == nil)
        #expect(!RuntimeManager.volta.canUninstallVersions)
    }

    @Test func aManagerThatDoesNotFitTheToolHasNoCommand() {
        #expect(script(.node, .rbenv) == nil)
        #expect(script(.ruby, .nvm, "3.4.1") == nil)
    }

    @Test func aVersionThatCouldRunShellCodeIsRefused() {
        #expect(script(.node, .nvm, "1.0.0; rm -rf ~") == nil)
        #expect(script(.node, .nvm, "") == nil)
        #expect(script(.node, .nvm, "$(whoami)") == nil)
    }

    @Test func anotherKindOfPackageIsNotAVersion() {
        #expect(script(.node, .nvm, kind: .npmGlobal) == nil)
    }

    @Test func theScannersRouteTheCommandToTheInstaller() {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let nodePackage = InstalledPackage(bucket: .node, kind: .runtime, name: "node", group: "fnm", installedVersion: "24.20.0")
        let rubyPackage = InstalledPackage(bucket: .ruby, kind: .runtime, name: "ruby", group: "rbenv", installedVersion: "3.4.1")

        #expect(NodeScanner(installations: [], runner: runner).uninstallCommand(for: nodePackage)?.arguments.last == "fnm uninstall 24.20.0")
        #expect(RubyScanner(installations: [], runner: runner).uninstallCommand(for: rubyPackage)?.arguments.last == "rbenv uninstall -f 3.4.1")
    }
}
