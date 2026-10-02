import Foundation
import Testing
@testable import DevHubCore

@Suite struct NodeToolsParserTests {
    @Test func readsTheRealPnpmList() throws {
        let packages = try NodeToolsParser.parsePnpmInstalled(try Fixture.data("pnpm-list-global.json"))

        #expect(packages == [
            NodeToolsParser.InstalledPackage(name: "@antfu/ni", version: "0.21.0"),
            NodeToolsParser.InstalledPackage(name: "cowsay", version: "1.5.0"),
            NodeToolsParser.InstalledPackage(name: "semver", version: "7.5.0")
        ])
    }

    @Test func readsAPnpmListWithNoPackages() throws {
        let empty = Data(#"[{"path":"/Users/example/Library/pnpm/global/v11","private":true,"dependencies":{}}]"#.utf8)

        #expect(try NodeToolsParser.parsePnpmInstalled(empty).isEmpty)
    }

    @Test func readsTheRealPnpmOutdatedList() throws {
        let updates = try NodeToolsParser.parsePnpmOutdated(try Fixture.data("pnpm-outdated-global.json"))

        #expect(updates == ["cowsay": "1.6.0", "semver": "7.8.5", "@antfu/ni": "30.6.0"])
        #expect(try NodeToolsParser.parsePnpmOutdated(Data("{}".utf8)).isEmpty)
    }

    @Test func readsTheRealYarnGlobalList() throws {
        let packages = NodeToolsParser.parseYarnInstalled(try Fixture.text("yarn-global-list.txt"))

        #expect(packages.map(\.name) == ["@antfu/ni", "cowsay", "semver"])
        #expect(packages.map(\.version) == ["0.21.0", "1.5.0", "7.5.0"])
        #expect(NodeToolsParser.parseYarnInstalled(try Fixture.text("yarn-global-list-empty.txt")).isEmpty)
    }

    @Test func readsTheYarnGlobalFolder() throws {
        #expect(NodeToolsParser.parseYarnGlobalFolder(try Fixture.text("yarn-global-dir.txt")) == "/Users/example/.config/yarn/global")
    }

    @Test func readsTheRealYarnOutdatedTable() throws {
        let updates = NodeToolsParser.parseYarnOutdated(try Fixture.text("yarn-outdated-global.jsonl"))

        #expect(updates == ["@antfu/ni": "30.6.0", "cowsay": "1.6.0", "semver": "7.8.5"])
    }

    @Test func yarnPrintsNothingWhenEverythingIsCurrent() throws {
        #expect(NodeToolsParser.parseYarnOutdated(try Fixture.text("yarn-outdated-global-current.jsonl")).isEmpty)
    }

    @Test func readsTheRealBunList() throws {
        let packages = NodeToolsParser.parseBunInstalled(try Fixture.text("bun-pm-ls-global.txt"))

        #expect(packages.map(\.name) == ["@angular/cli", "@antfu/ni", "cowsay", "semver"])
        #expect(packages.map(\.version) == ["17.0.0", "0.21.0", "1.5.0", "7.5.0"])
    }

    @Test func readsTheRealBunOutdatedTable() throws {
        let updates = NodeToolsParser.parseBunOutdated(try Fixture.text("bun-outdated-global.txt"))

        #expect(updates == ["@angular/cli": "22.2.1", "@antfu/ni": "30.6.0", "cowsay": "1.6.0", "semver": "7.8.5"])
    }

    @Test func bunPrintsOnlyTheHeaderWhenEverythingIsCurrent() {
        #expect(NodeToolsParser.parseBunOutdated("bun outdated v1.4.2 (744846f84)\n").isEmpty)
    }
}

@Suite struct NodePackageManagerLocatorTests {
    @Test func findsEachManagerInItsOwnFolder() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("Library/pnpm/pnpm")
        try home.makeExecutable(".bun/bin/bun")
        try home.makeExecutable(".yarn/bin/yarn")

        let found = NodePackageManagerLocator.locate(home: home.url, systemFolders: [])

        #expect(found.map(\.manager) == [.pnpm, .bun, .yarn])
        #expect(found[0].executable == home.url.appending(path: "Library/pnpm/pnpm"))
    }

    @Test func findsAManagerInstalledInsideANodeVersion() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".nvm/versions/node/v22.0.0/bin/npm")
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/npm")
        try home.makeExecutable(".nvm/versions/node/v22.0.0/bin/yarn")
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/yarn")
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/pnpm")
        let versions = NodeVersionDiscovery(home: home.url).installations()

        let found = NodePackageManagerLocator.locate(nodeInstallations: versions, home: home.url, systemFolders: [])

        #expect(found.map(\.manager) == [.pnpm, .yarn])
        #expect(found.map(\.executable) == [
            home.url.appending(path: ".nvm/versions/node/v24.21.0/bin/pnpm"),
            home.url.appending(path: ".nvm/versions/node/v24.21.0/bin/yarn")
        ])
    }

    @Test func findsNothingWhenNoManagerIsInstalled() throws {
        let home = try TemporaryHome()
        defer { home.remove() }

        #expect(NodePackageManagerLocator.locate(home: home.url, systemFolders: []).isEmpty)
    }

    @Test func theSidebarNamesAreStable() {
        #expect(NodePackageManager.allCases.map(\.displayName) == ["pnpm", "Bun", "Yarn"])
    }
}

@Suite struct NodeToolsScannerTests {
    private let pnpm = NodePackageManagerInstallation(manager: .pnpm, executable: URL(filePath: "/home/Library/pnpm/pnpm"))
    private let bun = NodePackageManagerInstallation(manager: .bun, executable: URL(filePath: "/home/.bun/bin/bun"))
    private let yarn = NodePackageManagerInstallation(manager: .yarn, executable: URL(filePath: "/home/.yarn/bin/yarn"))

    private func runner(yarnVersion: String = "1.22.22\n", bunHasNoPackages: Bool = false, pnpmFails: Bool = false, empty: Bool = false) -> FakeRunner {
        FakeRunner { command in
            let arguments = command.arguments
            switch (command.executable.lastPathComponent, arguments.first) {
            case ("pnpm", "list"):
                if pnpmFails { return failed(exitCode: 1, standardError: "ERR_PNPM_BROKEN") }
                return succeeded(empty ? #"[{"path":"/x","private":true,"dependencies":{}}]"# : ((try? Fixture.text("pnpm-list-global.json")) ?? ""))
            case ("pnpm", "outdated"):
                return CommandResult(exitCode: 1, standardOutput: (try? Fixture.text("pnpm-outdated-global.json")) ?? "", standardError: "")
            case ("yarn", "--version"):
                return succeeded(yarnVersion)
            case ("yarn", "global") where arguments.contains("list"):
                return succeeded((try? Fixture.text(empty ? "yarn-global-list-empty.txt" : "yarn-global-list.txt")) ?? "")
            case ("yarn", "global") where arguments.contains("dir"):
                return succeeded((try? Fixture.text("yarn-global-dir.txt")) ?? "")
            case ("yarn", "--cwd"):
                return CommandResult(exitCode: 1, standardOutput: (try? Fixture.text("yarn-outdated-global.jsonl")) ?? "", standardError: "")
            case ("bun", "pm"):
                if bunHasNoPackages { return failed(exitCode: 1, standardError: (try? Fixture.text("bun-pm-ls-global-empty.stderr.txt")) ?? "") }
                return succeeded((try? Fixture.text("bun-pm-ls-global.txt")) ?? "")
            case ("bun", "outdated"):
                return succeeded((try? Fixture.text("bun-outdated-global.txt")) ?? "")
            default:
                return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    @Test func listsPnpmPackagesWithTheirNewestVersion() async throws {
        let result = await NodeToolsScanner(installations: [pnpm], runner: runner()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.map(\.name) == ["@antfu/ni", "cowsay", "semver"])
        #expect(result.packages.allSatisfy { $0.bucket == .node && $0.group == "pnpm" && $0.kind == .pnpmGlobal })
        let cowsay = try #require(result.packages.first { $0.name == "cowsay" })
        #expect(cowsay.installedVersion == "1.5.0")
        #expect(cowsay.availableUpdate == "1.6.0")
    }

    @Test func listsYarnPackagesWithTheirNewestVersion() async throws {
        let result = await NodeToolsScanner(installations: [yarn], runner: runner()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.map(\.name) == ["@antfu/ni", "cowsay", "semver"])
        #expect(result.packages.allSatisfy { $0.group == "Yarn" && $0.kind == .yarnGlobal })
        #expect(result.packages.first { $0.name == "semver" }?.availableUpdate == "7.8.5")
    }

    @Test func runsYarnOutdatedInsideTheGlobalFolder() async {
        let fake = runner()

        _ = await NodeToolsScanner(installations: [yarn], runner: fake).scan()

        let outdated = fake.commands.first { $0.arguments.contains("outdated") }
        #expect(outdated?.arguments == ["--cwd", "/Users/example/.config/yarn/global", "outdated", "--json"])
    }

    @Test func listsBunPackagesWithTheirNewestVersion() async throws {
        let result = await NodeToolsScanner(installations: [bun], runner: runner()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.map(\.name) == ["@angular/cli", "@antfu/ni", "cowsay", "semver"])
        #expect(result.packages.allSatisfy { $0.group == "Bun" && $0.kind == .bunGlobal })
        #expect(result.packages.first { $0.name == "@angular/cli" }?.availableUpdate == "22.2.1")
    }

    @Test func yarnBerryHasNoGlobalPackages() async {
        let fake = runner(yarnVersion: "4.5.0\n")

        let result = await NodeToolsScanner(installations: [yarn], runner: fake).scan()

        #expect(result.packages.isEmpty)
        #expect(result.issues.isEmpty)
        #expect(!fake.commands.contains { $0.arguments.first == "global" })
    }

    @Test func bunWithoutGlobalPackagesIsNotAnIssue() async {
        let result = await NodeToolsScanner(installations: [bun], runner: runner(bunHasNoPackages: true)).scan()

        #expect(result.packages.isEmpty)
        #expect(result.issues.isEmpty)
    }

    @Test func managersWithoutGlobalPackagesSkipTheOutdatedCheck() async {
        let fake = runner(empty: true)

        let result = await NodeToolsScanner(installations: [pnpm, yarn], runner: fake).scan()

        #expect(result.packages.isEmpty)
        #expect(!fake.commands.contains { $0.arguments.contains("outdated") })
    }

    @Test func aBrokenManagerDoesNotHideTheOthers() async {
        let result = await NodeToolsScanner(installations: [pnpm, yarn, bun], runner: runner(pnpmFails: true)).scan()

        #expect(result.issues.map(\.group) == ["pnpm"])
        #expect(Set(result.packages.compactMap(\.group)) == ["Yarn", "Bun"])
    }

    @Test func groupsFollowTheNamesInTheSidebar() async {
        let result = await NodeToolsScanner(installations: [yarn, pnpm, bun], runner: runner()).scan()

        let order = result.packages.compactMap(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        #expect(order == ["Bun", "pnpm", "Yarn"])
    }

    private func package(_ name: String, group: String, kind: PackageKind) -> InstalledPackage {
        InstalledPackage(bucket: .node, kind: kind, name: name, group: group, installedVersion: "1.5.0", availableUpdate: "1.6.0")
    }

    @Test func updatesToTheExactNewestVersion() throws {
        let scanner = NodeToolsScanner(installations: [pnpm, bun, yarn], runner: runner())

        #expect(scanner.updateCommand(for: package("cowsay", group: "pnpm", kind: .pnpmGlobal))?.arguments == ["add", "-g", "cowsay@1.6.0"])
        #expect(scanner.updateCommand(for: package("cowsay", group: "Bun", kind: .bunGlobal))?.arguments == ["add", "-g", "cowsay@1.6.0"])
        #expect(scanner.updateCommand(for: package("cowsay", group: "Yarn", kind: .yarnGlobal))?.arguments == ["global", "add", "cowsay@1.6.0"])
        #expect(scanner.updateCommand(for: package("cowsay", group: "Yarn", kind: .yarnGlobal))?.executable == yarn.executable)
    }

    @Test func uninstallsWithTheOwnCommandOfEachManager() {
        let scanner = NodeToolsScanner(installations: [pnpm, bun, yarn], runner: runner())

        #expect(scanner.uninstallCommand(for: package("cowsay", group: "pnpm", kind: .pnpmGlobal))?.arguments == ["remove", "-g", "cowsay"])
        #expect(scanner.uninstallCommand(for: package("cowsay", group: "Bun", kind: .bunGlobal))?.arguments == ["remove", "-g", "cowsay"])
        #expect(scanner.uninstallCommand(for: package("cowsay", group: "Yarn", kind: .yarnGlobal))?.arguments == ["global", "remove", "cowsay"])
    }

    @Test func leavesPackagesOfNpmAndOtherToolsAlone() {
        let scanner = NodeToolsScanner(installations: [pnpm], runner: runner())
        let npmPackage = package("typescript", group: "24.21.0", kind: .npmGlobal)
        let formula = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", group: "pnpm", installedVersion: "1", availableUpdate: "2")

        #expect(scanner.updateCommand(for: npmPackage) == nil)
        #expect(scanner.uninstallCommand(for: npmPackage) == nil)
        #expect(scanner.updateCommand(for: formula) == nil)
    }

    @Test func addsTheNewestNodeAfterTheFoldersOfTheManager() throws {
        let node = URL(filePath: "/home/.nvm/versions/node/v24.21.0/bin")
        let scanner = NodeToolsScanner(installations: [yarn], runner: runner(), nodeBinDirectory: node)

        let command = try #require(scanner.uninstallCommand(for: package("cowsay", group: "Yarn", kind: .yarnGlobal)))

        let path = try #require(command.environment["PATH"]).split(separator: ":").map(String.init)
        #expect(path.first == "/home/.yarn/bin")
        #expect(path.firstIndex(of: node.path) != nil)
        #expect(try #require(path.firstIndex(of: node.path)) > 0)
    }

    @Test func givesPnpmItsHomeAndItsGlobalBinFolder() throws {
        let home = URL(filePath: "/Users/example")
        let scanner = NodeToolsScanner(installations: [pnpm], runner: runner(), home: home)

        let command = try #require(scanner.updateCommand(for: package("cowsay", group: "pnpm", kind: .pnpmGlobal)))

        #expect(command.environment["PNPM_HOME"] == "/Users/example/Library/pnpm")
        #expect(command.environment["PATH"]?.contains("/Users/example/Library/pnpm/bin") == true)
        #expect(command.context == "pnpm")
    }
}

@Suite struct CombinedScannerTests {
    private struct Stub: PackageScanner {
        let bucket = Bucket.node
        let packages: [InstalledPackage]
        let issues: [ScanIssue]
        let handles: String

        func scan(_ reason: ScanReason) async -> ScanResult { ScanResult(packages: packages, issues: issues) }

        func updateCommand(for package: InstalledPackage) -> ToolCommand? {
            package.group == handles ? ToolCommand(executable: URL(filePath: "/bin/\(handles)"), arguments: ["update"], environment: [:]) : nil
        }

        func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
            package.group == handles ? ToolCommand(executable: URL(filePath: "/bin/\(handles)"), arguments: ["remove"], environment: [:]) : nil
        }
    }

    private func package(_ name: String, group: String) -> InstalledPackage {
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: name, group: group, installedVersion: "1")
    }

    @Test func mergesPackagesAndIssuesOfEveryScanner() async {
        let first = Stub(packages: [package("a", group: "24.0.0")], issues: [ScanIssue(group: "24.0.0", message: "one")], handles: "24.0.0")
        let second = Stub(packages: [package("b", group: "pnpm")], issues: [ScanIssue(group: "pnpm", message: "two")], handles: "pnpm")

        let result = await CombinedScanner(bucket: .node, scanners: [first, second]).scan(.check)

        #expect(Set(result.packages.map(\.name)) == ["a", "b"])
        #expect(result.issues.count == 2)
    }

    @Test func asksEachScannerForTheCommandOfItsOwnPackages() {
        let first = Stub(packages: [], issues: [], handles: "24.0.0")
        let second = Stub(packages: [], issues: [], handles: "pnpm")
        let combined = CombinedScanner(bucket: .node, scanners: [first, second])

        #expect(combined.updateCommand(for: package("a", group: "pnpm"))?.executable.lastPathComponent == "pnpm")
        #expect(combined.uninstallCommand(for: package("a", group: "24.0.0"))?.executable.lastPathComponent == "24.0.0")
        #expect(combined.updateCommand(for: package("a", group: "Yarn")) == nil)
    }
}

@Suite struct PackageGroupOrderTests {
    @Test func versionsComeFirstNewestFirstAndNamesFollowAlphabetically() {
        let groups = ["Yarn", "22.11.0", "pnpm", "24.21.0", "Bun", "9.0.0"]

        #expect(groups.sorted(by: PackageGroup.precedes) == ["24.21.0", "22.11.0", "9.0.0", "Bun", "pnpm", "Yarn"])
    }

    @Test func pythonManagersStayAlphabetical() {
        #expect(["uv", "pipx"].sorted(by: PackageGroup.precedes) == ["pipx", "uv"])
    }
}

@Suite struct NodeToolsToolchainTests {
    private func executable(_ home: TemporaryHome, _ path: String) throws -> String {
        try home.makeExecutable(path)
        return home.url.appending(path: path).path
    }

    private func settingsWithNoManagers() -> SettingsValues {
        var settings = SettingsValues()
        settings.nodeFolder = "/nonexistent/node"
        settings.pnpmPath = "/nonexistent/bin/pnpm"
        settings.bunPath = "/nonexistent/bin/bun"
        settings.yarnPath = "/nonexistent/bin/yarn"
        return settings
    }

    @Test func aNodeManagerAloneIsEnoughForTheNodeTool() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        var settings = settingsWithNoManagers()
        settings.bunPath = try executable(home, "bin/bun")

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.nodeManagers.map(\.manager) == [.bun])
        #expect(toolchain.setupProblems[.node] == nil)
        #expect(toolchain.scanners(runner: CommandRunner())[.node] is NodeToolsScanner)
    }

    @Test func versionsAndManagersTogetherShareOneScanner() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v24.0.0/bin/npm")
        var settings = settingsWithNoManagers()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.pnpmPath = try executable(home, "bin/pnpm")

        let scanners = Toolchain.detect(settings: settings).scanners(runner: CommandRunner())

        #expect(scanners[.node] is CombinedScanner)
    }

    @Test func theManagersGetTheNewestNodeOnTheirPath() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v22.0.0/bin/npm")
        try home.makeExecutable("node/v24.0.0/bin/npm")
        var settings = settingsWithNoManagers()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.yarnPath = try executable(home, "bin/yarn")
        let yarnPackage = InstalledPackage(bucket: .node, kind: .yarnGlobal, name: "x", group: "Yarn", installedVersion: "1")

        let scanners = Toolchain.detect(settings: settings).scanners(runner: CommandRunner())
        let command = try #require((scanners[.node] as? CombinedScanner)?.uninstallCommand(for: yarnPackage))

        #expect(command.environment["PATH"]?.contains("node/v24.0.0/bin") == true)
        #expect(command.environment["PATH"]?.contains("node/v22.0.0/bin") == false)
    }

    @Test func nothingFoundStillExplainsWhyNodeIsMissing() {
        let toolchain = Toolchain.detect(settings: settingsWithNoManagers())

        #expect(toolchain.nodeManagers.isEmpty)
        #expect(toolchain.setupProblems[.node] != nil)
    }

    @Test func aChosenProgramThatIsMissingIsExplained() {
        var settings = settingsWithNoManagers()
        settings.nodeFolder = nil
        settings.yarnPath = "/nonexistent/bin/yarn"

        let toolchain = Toolchain.detect(settings: settings, applyingExclusions: false)

        #expect(!toolchain.nodeManagers.contains { $0.manager == .yarn })
    }

    @Test func aManagerTurnedOffIsLeftOut() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        var settings = settingsWithNoManagers()
        settings.pnpmPath = try executable(home, "bin/pnpm")
        settings.yarnPath = try executable(home, "bin/yarn")
        settings.excludedNodeManagers = ["pnpm"]

        #expect(Toolchain.detect(settings: settings).nodeManagers.map(\.manager) == [.yarn])
        #expect(Toolchain.detect(settings: settings, applyingExclusions: false).nodeManagers.map(\.manager) == [.pnpm, .yarn])
    }

    @Test func turningNodeOffTurnsItsManagersOff() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        var settings = settingsWithNoManagers()
        settings.pnpmPath = try executable(home, "bin/pnpm")
        settings.disabledBuckets = [.node]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.nodeManagers.isEmpty)
        #expect(toolchain.setupProblems[.node] == nil)
    }

    @Test func knownGroupsListVersionsThenManagers() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v24.0.0/bin/npm")
        try home.makeExecutable("node/v22.0.0/bin/npm")
        var settings = settingsWithNoManagers()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.pnpmPath = try executable(home, "bin/pnpm")
        settings.yarnPath = try executable(home, "bin/yarn")

        let groups = Toolchain.detect(settings: settings).knownGroups

        #expect(groups[.node] == ["24.0.0", "22.0.0", "pnpm", "Yarn"])
    }
}

@Suite struct NodeToolsSettingsTests {
    @Test func aSettingsFileFromBeforeNodeManagersStillLoads() throws {
        let old = Data(#"{"theme":"dark","pipxPath":"/x/pipx"}"#.utf8)

        let settings = try JSONDecoder().decode(SettingsValues.self, from: old)

        #expect(settings.pnpmPath == nil)
        #expect(settings.bunPath == nil)
        #expect(settings.yarnPath == nil)
        #expect(settings.excludedNodeManagers.isEmpty)
    }

    @Test func changingTheNodeManagerSettingsScansAgain() {
        let base = SettingsValues()
        var pnpm = base
        pnpm.pnpmPath = "/somewhere/pnpm"
        var bun = base
        bun.bunPath = "/somewhere/bun"
        var yarn = base
        yarn.yarnPath = "/somewhere/yarn"
        var excluded = base
        excluded.excludedNodeManagers = ["bun"]

        #expect(pnpm.scanningFields != base.scanningFields)
        #expect(bun.scanningFields != base.scanningFields)
        #expect(yarn.scanningFields != base.scanningFields)
        #expect(excluded.scanningFields != base.scanningFields)
    }
}

@Suite struct NodeManagerPathValidationTests {
    private func script(_ home: TemporaryHome, _ body: String) throws -> String {
        let file = home.url.appending(path: "tool")
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    @Test func acceptsAProgramThatPrintsAVersion() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let path = try script(home, "#!/bin/sh\necho 12.6.0\n")

        #expect(await PathValidation.nodeManager(.pnpm, path: path, runner: CommandRunner()) == .found("pnpm 12.6.0"))
    }

    @Test func rejectsAProgramThatPrintsSomethingElse() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let path = try script(home, "#!/bin/sh\necho 'usage: tool'\n")

        #expect(await PathValidation.nodeManager(.bun, path: path, runner: CommandRunner()) == .problem("This program did not run as Bun."))
    }

    @Test func explainsAPathThatDoesNotExist() async {
        #expect(await PathValidation.nodeManager(.yarn, path: "/nonexistent/yarn", runner: CommandRunner()) == .problem("Nothing was found at this path."))
    }
}
