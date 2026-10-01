import Foundation
import Testing
@testable import DevHubCore

@Suite struct BrewParserTests {
    private let prefix = URL(filePath: "/opt/homebrew")

    @Test func readsTheRealOutdatedList() throws {
        let items = try BrewParser.parseOutdated(Fixture.data("brew-outdated.json"))

        #expect(items.count == 105)
        #expect(items.first == BrewParser.OutdatedItem(name: "adns", kind: .formula, currentVersion: "1.7.0", isPinned: false))
        #expect(items.allSatisfy { $0.kind == .formula })
    }

    @Test func readsOutdatedCasksWhetherTheInstalledVersionIsATextOrAList() throws {
        let items = try BrewParser.parseOutdated(Fixture.data("brew-outdated-casks.synthetic.json"))

        #expect(items.map(\.name) == ["visual-studio-code", "raycast"])
        #expect(items.allSatisfy { $0.kind == .cask })
        #expect(items.map(\.currentVersion) == ["1.94.0", "1.84.0"])
    }

    @Test func readsInstalledFormulaeWithTheirDetails() throws {
        let packages = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)
        let git = try #require(packages.first { $0.name == "git" })

        #expect(packages.count == 8)
        #expect(git.kind == .formula)
        #expect(git.installedVersion == "2.47.0")
        #expect(git.summary == "Distributed revision control system")
        #expect(git.homepage == "https://git-scm.com")
        #expect(git.installPath == "/opt/homebrew/Cellar/git/2.47.0")
        #expect(git.isOutdated == false)
    }

    @Test func tellsRequestedPackagesFromDependencies() throws {
        let packages = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)

        #expect(packages.first { $0.name == "git" }?.installedOnRequest == true)
        #expect(packages.first { $0.name == "oniguruma" }?.installedOnRequest == false)
    }

    @Test func findsWhichInstalledPackagesNeedAFormula() throws {
        let packages = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)

        #expect(packages.first { $0.name == "libunistring" }?.requiredBy == ["gettext", "git"])
        #expect(packages.first { $0.name == "pcre2" }?.requiredBy == ["git"])
        #expect(packages.first { $0.name == "git" }?.requiredBy == [])
    }

    @Test func readsInstalledCasks() throws {
        let packages = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)
        let claude = try #require(packages.first { $0.name == "claude-code" })

        #expect(claude.kind == .cask)
        #expect(claude.installedVersion == "2.1.285")
        #expect(claude.installPath == "/opt/homebrew/Caskroom/claude-code/2.1.285")
    }

    @Test func sortsPackagesByName() throws {
        let packages = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)

        #expect(packages.map(\.name) == packages.map(\.name).sorted())
    }

    @Test func mergeMarksOnlyThePackagesInTheOutdatedList() throws {
        let installed = try BrewParser.parseInstalled(Fixture.data("brew-info-installed.json"), prefix: prefix)
        let outdated = try BrewParser.parseOutdated(Fixture.data("brew-outdated.json"))

        let merged = BrewParser.merge(installed: installed, outdated: outdated)

        #expect(merged.first { $0.name == "git" }?.availableUpdate == "2.56.0")
        #expect(merged.first { $0.name == "pcre2" }?.availableUpdate == "10.49")
        #expect(merged.first { $0.name == "gettext" }?.availableUpdate == nil)
        #expect(merged.count == installed.count)
    }

    @Test func aPinnedPackageReportsNoUpdate() {
        let package = InstalledPackage(bucket: .homebrew, kind: .formula, name: "node", installedVersion: "22.0.0")
        let outdated = [BrewParser.OutdatedItem(name: "node", kind: .formula, currentVersion: "23.0.0", isPinned: true)]

        let merged = BrewParser.merge(installed: [package], outdated: outdated)

        #expect(merged.first?.availableUpdate == nil)
        #expect(merged.first?.isPinned == true)
    }

    @Test func aFormulaAndACaskWithTheSameNameStaySeparate() {
        let formula = InstalledPackage(bucket: .homebrew, kind: .formula, name: "docker", installedVersion: "1.0")
        let cask = InstalledPackage(bucket: .homebrew, kind: .cask, name: "docker", installedVersion: "4.0")
        let outdated = [BrewParser.OutdatedItem(name: "docker", kind: .cask, currentVersion: "5.0", isPinned: false)]

        let merged = BrewParser.merge(installed: [formula, cask], outdated: outdated)

        #expect(merged.first { $0.kind == .formula }?.availableUpdate == nil)
        #expect(merged.first { $0.kind == .cask }?.availableUpdate == "5.0")
    }

    @Test func rejectsOutputThatIsNotJSON() {
        #expect(throws: (any Error).self) {
            try BrewParser.parseOutdated(Data("==> Downloading Homebrew API data".utf8))
        }
    }
}
