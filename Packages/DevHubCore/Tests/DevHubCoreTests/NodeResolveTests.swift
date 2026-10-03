import Foundation
import Testing
@testable import DevHubCore

@Suite struct NpmViewParserTests {
    @Test func readsAListOfVersionStringsFromAPackageWithoutEngines() throws {
        let versions = try NpmParser.parsePublishedVersions(try Fixture.data("npm-view-all-left-pad.json"))

        #expect(versions.count == 15)
        #expect(versions.allSatisfy { $0.nodeRange == nil })
        #expect(versions.contains { $0.version == "1.3.0" })
    }

    @Test func stillReadsVersionsWithTheirEngines() throws {
        let versions = try NpmParser.parsePublishedVersions(try Fixture.data("npm-view-all-serve.json"))

        #expect(versions.map(\.version) == ["14.2.0", "14.2.1", "14.2.2", "14.2.3", "14.2.4", "14.2.5", "14.2.6"])
        #expect(versions.allSatisfy { $0.nodeRange == ">= 14" })
    }

    @Test func readsTheNewestVersionWithOrWithoutEngines() throws {
        let withEngines = try NpmParser.parsePublishedVersions(try Fixture.data("npm-view-latest-eslint.json"))
        let without = try NpmParser.parsePublishedVersions(try Fixture.data("npm-view-latest-left-pad.json"))

        #expect(withEngines.map(\.version) == ["10.12.0"])
        #expect(withEngines.first?.nodeRange == "^20.19.0 || ^22.13.0 || >=24")
        #expect(without.map(\.version) == ["1.3.0"])
        #expect(without.first?.nodeRange == nil)
    }

    @Test func readsTheVersionList() throws {
        let versions = NpmParser.parseVersionList(try Fixture.data("npm-view-versions-eslint.json"))

        #expect(versions.count == 431)
        #expect(versions.first == "0.0.4")
        #expect(versions.last == "10.12.0")
    }

    @Test func readsAVersionListThatIsOneString() {
        #expect(NpmParser.parseVersionList(Data(#""1.0.0""#.utf8)) == ["1.0.0"])
        #expect(NpmParser.parseVersionList(Data("oops".utf8)).isEmpty)
        #expect(NpmParser.parseVersionList(Data()).isEmpty)
    }
}

@Suite struct VersionSearchTests {
    @Test func keepsTheNewestPatchOfEachMinorBelowTheLatestAndSkipsPrereleases() {
        let versions = ["1.0.0", "1.0.1", "1.1.0", "1.1.3", "2.0.0-rc.1", "2.0.0", "2.1.0", "3.0.0", "3.1.0"]

        #expect(VersionSearch.candidates(below: "3.0.0", among: versions) == ["2.1.0", "2.0.0", "1.1.3", "1.0.1"])
    }

    @Test func aPrereleaseIsNeverACandidateEvenWhenItIsTheOnlyVersionOfItsMinor() {
        #expect(VersionSearch.candidates(below: "3.0.0", among: ["2.1.0", "2.2.0-beta.1", "2.2.0-beta.2"]) == ["2.1.0"])
    }

    @Test func theNewestPatchWinsWhateverTheOrderOfTheList() {
        #expect(VersionSearch.candidates(below: "2.0.0", among: ["1.1.3", "1.1.0", "1.0.1", "1.0.0"]) == ["1.1.3", "1.0.1"])
        #expect(VersionSearch.candidates(below: "2.0.0", among: ["1.0.0", "1.0.1", "1.1.0", "1.1.3"]) == ["1.1.3", "1.0.1"])
    }

    @Test func ordersByVersionNumberNotByText() {
        #expect(VersionSearch.candidates(below: "10.0.0", among: ["9.10.0", "9.9.0", "2.0.0"]) == ["9.10.0", "9.9.0", "2.0.0"])
    }

    @Test func ignoresTextThatIsNotAVersion() {
        #expect(VersionSearch.candidates(below: "2.0.0", among: ["next", "latest", "1.x", "1.2.3"]) == ["1.2.3"])
    }

    @Test func worksOnTheRealVersionListOfAWidelyUsedPackage() throws {
        let versions = NpmParser.parseVersionList(try Fixture.data("npm-view-versions-eslint.json"))

        let candidates = VersionSearch.candidates(below: "10.12.0", among: versions)

        #expect(Array(candidates.prefix(3)) == ["10.11.0", "10.10.0", "10.9.1"])
        #expect(candidates.contains("9.39.5"))
        #expect(!candidates.contains("10.12.0"))
        #expect(candidates.allSatisfy { !$0.contains("-") })
        #expect(candidates.count < versions.count)
    }
}

@Suite struct NodeResolveTests {
    private func node(_ version: String) -> NodeInstallation {
        NodeInstallation(version: version, manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v\(version)"))
    }

    private func package(_ name: String, group: String = "18.20.4", bucket: Bucket = .node) -> InstalledPackage {
        InstalledPackage(bucket: bucket, kind: .npmGlobal, name: name, group: group, installedVersion: "")
    }

    /// A registry that answers the three kinds of `npm view` call that a lookup makes.
    private struct Registry {
        var latest: CommandResult
        var versions: CommandResult = failed(exitCode: 1, standardError: "unexpected")
        var engines: @Sendable (String) -> CommandResult = { _ in failed(exitCode: 1, standardError: "unexpected") }

        func runner() -> FakeRunner {
            FakeRunner { command in
                let arguments = command.arguments
                guard arguments.first == "view", arguments.count >= 3 else { return failed(exitCode: 1, standardError: "unexpected command") }
                if arguments[2] == "versions" { return versions }
                if let at = arguments[1].lastIndex(of: "@"), at != arguments[1].startIndex { return engines(String(arguments[1][arguments[1].index(after: at)...])) }
                return latest
            }
        }
    }

    private func scanner(node version: String, _ registry: Registry) -> (NodeScanner, FakeRunner) {
        let fake = registry.runner()
        return (NodeScanner(installations: [node(version)], runner: fake), fake)
    }

    private static func one(_ version: String, engines: String? = nil) -> String {
        engines.map { #"[{"version":"\#(version)","engines.node":"\#($0)"}]"# } ?? #"["\#(version)"]"#
    }

    @Test func theNewestVersionInstallsWhenTheNodeVersionRunsIt() async throws {
        let (scanner, fake) = scanner(node: "24.21.0", Registry(latest: succeeded(try Fixture.text("npm-view-latest-eslint.json"))))

        let resolution = await scanner.resolveInstall(of: package("eslint", group: "24.21.0"))

        #expect(resolution == .current(version: "10.12.0"))
        #expect(fake.commands.count == 1)
        #expect(fake.commands.first?.arguments == ["view", "eslint", "version", "engines.node", "--json"])
    }

    @Test func aPackageWithoutEnginesInstallsTheNewest() async throws {
        let (scanner, fake) = scanner(node: "18.20.4", Registry(latest: succeeded(try Fixture.text("npm-view-latest-left-pad.json"))))

        #expect(await scanner.resolveInstall(of: package("left-pad")) == .current(version: "1.3.0"))
        #expect(fake.commands.count == 1)
    }

    @Test func anOlderVersionInstallsWhenTheNewestNeedsANewerNode() async throws {
        let list = try Fixture.text("npm-view-versions-eslint.json")
        let registry = Registry(
            latest: succeeded(try Fixture.text("npm-view-latest-eslint.json")),
            versions: succeeded(list),
            engines: { version in
                let major = Int(version.split(separator: ".")[0]) ?? 0
                return succeeded(Self.one(version, engines: major >= 10 ? "^20.19.0 || ^22.13.0 || >=24" : "^18.18.0 || ^20.9.0 || >=21.1.0"))
            }
        )
        let (scanner, fake) = scanner(node: "18.20.4", registry)

        let resolution = await scanner.resolveInstall(of: package("eslint"))

        #expect(resolution == .older(newest: "10.12.0", installs: "9.39.5"))
        #expect(resolution?.installVersion == "9.39.5")
        #expect(fake.commands.count <= 2 + 3 * 6)
    }

    @Test func theSearchStopsAtTheFirstBatchThatHasAMatch() async throws {
        let registry = Registry(
            latest: succeeded(Self.one("3.0.0", engines: ">=22")),
            versions: succeeded(#"["1.0.0","1.1.0","2.0.0","2.1.0","2.2.0","3.0.0"]"#),
            engines: { version in succeeded(Self.one(version, engines: version.hasPrefix("2") ? ">=22" : ">=14")) }
        )
        let (scanner, fake) = scanner(node: "18.20.4", registry)

        let resolution = await scanner.resolveInstall(of: package("pkg"))

        #expect(resolution == .older(newest: "3.0.0", installs: "1.1.0"))
        #expect(fake.commands.count == 2 + 5)
    }

    @Test func noVersionThatTheNodeVersionCanRunIsIncompatible() async {
        let registry = Registry(
            latest: succeeded(Self.one("2.0.0", engines: ">=22")),
            versions: succeeded(#"["1.0.0","1.1.0","2.0.0"]"#),
            engines: { version in succeeded(Self.one(version, engines: ">=22")) }
        )
        let (scanner, _) = scanner(node: "18.20.4", registry)

        let resolution = await scanner.resolveInstall(of: package("pkg"))

        #expect(resolution == .incompatible(newest: "2.0.0"))
        #expect(resolution?.installVersion == nil)
    }

    @Test func theSearchGivesUpAfterAFewBatches() async throws {
        let registry = Registry(
            latest: succeeded(Self.one("99.0.0", engines: ">=200")),
            versions: succeeded(try Fixture.text("npm-view-versions-eslint.json")),
            engines: { version in succeeded(Self.one(version, engines: ">=200")) }
        )
        let (scanner, fake) = scanner(node: "18.20.4", registry)

        #expect(await scanner.resolveInstall(of: package("eslint")) == .incompatible(newest: "99.0.0"))
        #expect(fake.commands.count == 2 + 8 * 6)
    }

    @Test func aPackageThatDoesNotExistIsNotFound() async throws {
        let stderr = try Fixture.text("npm-view-404.stderr.txt")
        let (scanner, fake) = scanner(node: "18.20.4", Registry(latest: CommandResult(exitCode: 1, standardOutput: "", standardError: stderr)))

        #expect(await scanner.resolveInstall(of: package("definitely-not-a-package-xyz-123")) == .notFound)
        #expect(fake.commands.count == 1)
    }

    @Test func anUnreachableRegistryIsUnavailable() async {
        let offline = failed(exitCode: 1, standardError: "npm error code ENOTFOUND\nnpm error network request failed")
        let (scanner, _) = scanner(node: "18.20.4", Registry(latest: offline))

        #expect(await scanner.resolveInstall(of: package("eslint"))?.isUnavailable == true)
    }

    @Test func aFailedSearchIsUnavailableAndNotIncompatible() async {
        let noList = Registry(latest: succeeded(Self.one("2.0.0", engines: ">=22")))
        let noEngines = Registry(
            latest: succeeded(Self.one("2.0.0", engines: ">=22")),
            versions: succeeded(#"["1.0.0","2.0.0"]"#),
            engines: { _ in failed(exitCode: 1, standardError: "npm error network") }
        )

        #expect(await scanner(node: "18.20.4", noList).0.resolveInstall(of: package("pkg"))?.isUnavailable == true)
        #expect(await scanner(node: "18.20.4", noEngines).0.resolveInstall(of: package("pkg"))?.isUnavailable == true)
    }

    @Test func aPackageOfAnotherToolOrVersionIsNotHandled() async {
        let (scanner, _) = scanner(node: "18.20.4", Registry(latest: succeeded(Self.one("1.0.0"))))

        #expect(await scanner.resolveInstall(of: package("eslint", group: "20.0.0")) == nil)
        #expect(await scanner.resolveInstall(of: package("git", group: "18.20.4", bucket: .homebrew)) == nil)
    }

    @Test func theCombinedScannerReturnsTheFirstScannerThatHandlesThePackage() async throws {
        let (npm, _) = scanner(node: "24.21.0", Registry(latest: succeeded(try Fixture.text("npm-view-latest-eslint.json"))))
        let tools = NodeToolsScanner(installations: [], runner: FakeRunner { _ in succeeded("") })
        let combined = CombinedScanner(bucket: .node, scanners: [tools, npm])

        #expect(await combined.resolveInstall(of: package("eslint", group: "24.21.0")) == .current(version: "10.12.0"))
        #expect(await combined.resolveInstall(of: package("eslint", group: "pnpm")) == nil)
    }
}
