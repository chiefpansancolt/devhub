import Foundation
import Testing
@testable import DevHubCore

@Suite struct PythonParserTests {
    @Test func readsTheRealPipxList() throws {
        let tools = try PythonParser.parsePipxList(try Fixture.data("pipx-list.json"))

        #expect(tools == [
            PythonParser.InstalledTool(name: "black", version: "24.1.0"),
            PythonParser.InstalledTool(name: "cowsay", version: "6.1"),
            PythonParser.InstalledTool(name: "httpie", version: "3.2.1"),
            PythonParser.InstalledTool(name: "pycowsay", version: "0.0.0.1")
        ])
    }

    @Test func rejectsOutputThatIsNotJSON() {
        #expect(throws: (any Error).self) { try PythonParser.parsePipxList(Data("nothing installed".utf8)) }
    }

    @Test func readsTheNewestVersionFromAUvBackedVenv() throws {
        #expect(PythonParser.parseLatestVersion(of: "httpie", in: try Fixture.data("pipx-outdated-httpie.json")) == "3.2.4")
        #expect(PythonParser.parseLatestVersion(of: "black", in: try Fixture.data("pipx-outdated-black.json")) == "26.5.1")
    }

    @Test func readsTheNewestVersionFromAPipBackedVenv() throws {
        #expect(PythonParser.parseLatestVersion(of: "pycowsay", in: try Fixture.data("pipx-outdated-pycowsay.json")) == "0.0.0.2")
    }

    @Test func anUpToDateToolHasNoNewerVersion() throws {
        #expect(PythonParser.parseLatestVersion(of: "cowsay", in: try Fixture.data("pipx-outdated-cowsay.json")) == nil)
    }

    @Test func ignoresDependenciesThatAreOutdated() {
        let json = Data(#"[{"name":"idna","version":"3.0","latest_version":"3.10"},{"name":"Some_Tool","version":"1.0","latest_version":"2.0"}]"#.utf8)

        #expect(PythonParser.parseLatestVersion(of: "some-tool", in: json) == "2.0")
        #expect(PythonParser.parseLatestVersion(of: "httpie", in: json) == nil)
    }

    @Test func readsTheRealUvList() throws {
        let tools = PythonParser.parseUvList(try Fixture.text("uv-tool-list.txt"))

        #expect(tools.map(\.tool) == [
            PythonParser.InstalledTool(name: "cowsay", version: "6.1"),
            PythonParser.InstalledTool(name: "pycowsay", version: "0.0.0.1"),
            PythonParser.InstalledTool(name: "ruff", version: "0.5.0")
        ])
        #expect(tools.allSatisfy { $0.latest == nil })
    }

    @Test func readsTheRealOutdatedUvList() throws {
        let tools = PythonParser.parseUvList(try Fixture.text("uv-tool-list-outdated.txt"))

        #expect(tools.map(\.tool.name) == ["pycowsay", "ruff"])
        #expect(tools.map(\.latest) == ["0.0.0.2", "0.16.10"])
    }

    @Test func readsTheRequirementsOfConstrainedTools() throws {
        let tools = PythonParser.parseUvList(try Fixture.text("uv-tool-list-outdated-constrained.txt"))

        #expect(tools.map(\.tool.name) == ["pycowsay", "ruff", "yt-dlp"])
        #expect(tools.map(\.requirement) == ["<0.0.0.2", "==0.5.0", ">=2025, <2026"])
        #expect(tools.map(\.latest) == ["0.0.0.2", "0.16.10", "2026.8.19"])
        #expect(tools.allSatisfy { !$0.latestIsReachable })
    }

    @Test func aLowerBoundDoesNotBlockTheNewestVersion() {
        let entry = PythonParser.parseUvList("tool v1.0.0 [required: >=1.0, !=1.5] [latest: 3.0.0]\n- tool\n")

        #expect(entry.first?.requirement == ">=1.0, !=1.5")
        #expect(entry.first?.latestIsReachable == true)
    }

    @Test func readsNothingFromAnEmptyUvList() throws {
        #expect(PythonParser.parseUvList(try Fixture.text("uv-tool-list-empty.txt")).isEmpty)
    }
}

@Suite struct PythonLocatorTests {
    @Test func findsEachManagerInItsUsualFolder() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".local/bin/pipx")
        try home.makeExecutable(".cargo/bin/uv")

        let found = PythonLocator.locate(home: home.url)

        #expect(found.map(\.manager) == [.pipx, .uv])
        #expect(found[0].executable == home.url.appending(path: ".local/bin/pipx"))
        #expect(found[1].executable == home.url.appending(path: ".cargo/bin/uv"))
    }

    @Test func findsOnlyTheManagerThatIsThere() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".local/bin/uv")

        #expect(PythonLocator.locate(home: home.url).map(\.manager) == [.uv])
    }
}

@Suite struct PythonScannerTests {
    private let pipx = PythonInstallation(manager: .pipx, executable: URL(filePath: "/home/.local/bin/pipx"))
    private let uv = PythonInstallation(manager: .uv, executable: URL(filePath: "/home/.local/bin/uv"))

    private func runner(uvOutdatedFails: Bool = false, pipxListFails: Bool = false, constrainedUvTools: Bool = false) -> FakeRunner {
        let uvSuffix = constrainedUvTools ? "-constrained" : ""
        return FakeRunner { command in
            let arguments = command.arguments
            switch (command.executable.lastPathComponent, arguments.first) {
            case ("pipx", "list"):
                return pipxListFails ? failed(exitCode: 1, standardError: "pipx is broken") : succeeded((try? Fixture.text("pipx-list.json")) ?? "")
            case ("pipx", "runpip"):
                return succeeded((try? Fixture.text("pipx-outdated-\(arguments[1]).json")) ?? "[]")
            case ("uv", "tool") where arguments.contains("--outdated"):
                return uvOutdatedFails
                    ? failed(exitCode: 2, standardError: "error: unexpected argument '--outdated' found")
                    : succeeded((try? Fixture.text("uv-tool-list-outdated\(uvSuffix).txt")) ?? "")
            case ("uv", "tool"):
                return succeeded((try? Fixture.text("uv-tool-list\(uvSuffix).txt")) ?? "")
            default:
                return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    @Test func listsPipxToolsWithTheirNewestVersion() async throws {
        let result = await PythonScanner(installations: [pipx], runner: runner()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.map(\.name) == ["black", "cowsay", "httpie", "pycowsay"])
        #expect(result.packages.allSatisfy { $0.group == "pipx" && $0.kind == .pythonTool })
        let black = try #require(result.packages.first { $0.name == "black" })
        #expect(black.installedVersion == "24.1.0")
        #expect(black.availableUpdate == "26.5.1")
        #expect(result.packages.first { $0.name == "cowsay" }?.isOutdated == false)
        #expect(black.homepage == "https://pypi.org/project/black/")
    }

    @Test func listsUvToolsAndMergesTheOutdatedOnes() async throws {
        let result = await PythonScanner(installations: [uv], runner: runner()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.map(\.name) == ["cowsay", "pycowsay", "ruff"])
        #expect(result.packages.first { $0.name == "ruff" }?.availableUpdate == "0.16.10")
        #expect(result.packages.first { $0.name == "cowsay" }?.isOutdated == false)
        #expect(result.packages.allSatisfy { $0.group == "uv" })
    }

    @Test func aUvToolWithARequirementKeepsNoUpdateThatUpgradeCannotInstall() async throws {
        let result = await PythonScanner(installations: [uv], runner: runner(constrainedUvTools: true)).scan()

        #expect(result.packages.map(\.name) == ["cowsay", "httpie", "pycowsay", "ruff", "yt-dlp"])
        #expect(result.packages.allSatisfy { !$0.isOutdated })
        #expect(try #require(result.packages.first { $0.name == "ruff" }).installedVersion == "0.5.0")
    }

    @Test func anOlderUvWithoutTheOutdatedFlagStillListsItsTools() async {
        let result = await PythonScanner(installations: [uv], runner: runner(uvOutdatedFails: true)).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.count == 3)
        #expect(result.packages.allSatisfy { !$0.isOutdated })
    }

    @Test func groupsByManagerWhenBothArePresent() async {
        let result = await PythonScanner(installations: [uv, pipx], runner: runner()).scan()

        #expect(result.packages.map(\.group) == Array(repeating: "pipx", count: 4) + Array(repeating: "uv", count: 3))
    }

    @Test func aBrokenManagerDoesNotHideTheOtherOne() async {
        let result = await PythonScanner(installations: [pipx, uv], runner: runner(pipxListFails: true)).scan()

        #expect(result.issues.map(\.group) == ["pipx"])
        #expect(result.packages.allSatisfy { $0.group == "uv" })
        #expect(result.packages.count == 3)
    }

    private func package(_ name: String, group: String) -> InstalledPackage {
        InstalledPackage(bucket: .python, kind: .pythonTool, name: name, group: group, installedVersion: "1", availableUpdate: "2")
    }

    @Test func buildsTheUpdateCommandForEachManager() throws {
        let scanner = PythonScanner(installations: [pipx, uv], runner: runner())

        let pipxCommand = try #require(scanner.updateCommand(for: package("black", group: "pipx")))
        let uvCommand = try #require(scanner.updateCommand(for: package("ruff", group: "uv")))

        #expect(pipxCommand.executable == pipx.executable)
        #expect(pipxCommand.arguments == ["upgrade", "black"])
        #expect(uvCommand.executable == uv.executable)
        #expect(uvCommand.arguments == ["tool", "upgrade", "ruff"])
    }

    @Test func buildsTheUninstallCommandForEachManager() {
        let scanner = PythonScanner(installations: [pipx, uv], runner: runner())

        #expect(scanner.uninstallCommand(for: package("black", group: "pipx"))?.arguments == ["uninstall", "black"])
        #expect(scanner.uninstallCommand(for: package("ruff", group: "uv"))?.arguments == ["tool", "uninstall", "ruff"])
    }

    @Test func aToolFromAManagerThatIsGoneHasNoCommand() {
        let scanner = PythonScanner(installations: [pipx], runner: runner())

        #expect(scanner.updateCommand(for: package("ruff", group: "uv")) == nil)
        #expect(scanner.uninstallCommand(for: package("ruff", group: "uv")) == nil)
    }

    @Test func refusesPackagesOfOtherTools() {
        let scanner = PythonScanner(installations: [pipx], runner: runner())
        let formula = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", group: "pipx", installedVersion: "1", availableUpdate: "2")

        #expect(scanner.updateCommand(for: formula) == nil)
    }

    @Test func putsTheManagerFolderFirstOnThePath() throws {
        let scanner = PythonScanner(installations: [pipx], runner: runner())

        let command = try #require(scanner.updateCommand(for: package("black", group: "pipx")))

        #expect(command.environment["PATH"]?.hasPrefix("/home/.local/bin:") == true)
        #expect(command.context == "pipx")
    }
}

@Suite struct PythonSettingsTests {
    @Test func aSettingsFileFromBeforePythonStillLoads() throws {
        let old = Data(#"{"theme":"dark","rustPath":"/x/rustup"}"#.utf8)

        let settings = try JSONDecoder().decode(SettingsValues.self, from: old)

        #expect(settings.pipxPath == nil)
        #expect(settings.uvPath == nil)
        #expect(settings.excludedPythonManagers.isEmpty)
    }

    @Test func changingThePythonSettingsScansAgain() {
        let base = SettingsValues()
        var pipx = base
        pipx.pipxPath = "/somewhere/pipx"
        var uv = base
        uv.uvPath = "/somewhere/uv"
        var excluded = base
        excluded.excludedPythonManagers = ["uv"]

        #expect(pipx.scanningFields != base.scanningFields)
        #expect(uv.scanningFields != base.scanningFields)
        #expect(excluded.scanningFields != base.scanningFields)
    }

    @Test func detectionHonoursAChosenProgram() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("bin/uv")
        var settings = SettingsValues()
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = home.url.appending(path: "bin/uv").path

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.python.map(\.manager) == [.uv])
        #expect(toolchain.python.first?.executable == home.url.appending(path: "bin/uv"))
        #expect(toolchain.setupProblems[.python] == nil)
    }

    @Test func detectionExplainsAChosenProgramThatIsMissing() {
        var settings = SettingsValues()
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.python.isEmpty)
        #expect(toolchain.setupProblems[.python] != nil)
    }

    @Test func aManagerTurnedOffIsLeftOut() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("bin/pipx")
        try home.makeExecutable("bin/uv")
        var settings = SettingsValues()
        settings.pipxPath = home.url.appending(path: "bin/pipx").path
        settings.uvPath = home.url.appending(path: "bin/uv").path
        settings.excludedPythonManagers = ["pipx"]

        #expect(Toolchain.detect(settings: settings).python.map(\.manager) == [.uv])
        #expect(Toolchain.detect(settings: settings, applyingExclusions: false).python.map(\.manager) == [.pipx, .uv])
    }

    @Test func turningEveryManagerOffSaysSo() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("bin/uv")
        var settings = SettingsValues()
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = home.url.appending(path: "bin/uv").path
        settings.excludedPythonManagers = ["uv"]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.python.isEmpty)
        #expect(toolchain.setupProblems[.python] == "Every Python tool manager is turned off in Settings.")
    }

    @Test func aPythonThatIsOffHasNoInstallationAndNoSetupProblem() {
        var settings = SettingsValues()
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"
        settings.disabledBuckets = [.python]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.python.isEmpty)
        #expect(toolchain.setupProblems[.python] == nil)
    }

    @Test func pythonScopesSplitByManager() {
        let tool = InstalledPackage(bucket: .python, kind: .pythonTool, name: "ruff", group: "uv", installedVersion: "1")

        #expect(PackageScope(bucket: .python, group: "uv").contains(tool))
        #expect(!PackageScope(bucket: .python, group: "pipx").contains(tool))
        #expect(PackageScope.groups(of: .python, versions: ["pipx", "uv"]).map(\.group) == ["pipx", "uv"])
    }
}

@Suite struct PythonPathValidationTests {
    private func script(_ home: TemporaryHome, _ body: String) throws -> String {
        let file = home.url.appending(path: "tool")
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    @Test func acceptsARealPipxAndARealUv() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let pipx = try script(home, "#!/bin/sh\ncat <<'EOF'\n\(try Fixture.text("pipx-version.txt"))EOF\n")
        #expect(await PathValidation.pythonManager(.pipx, path: pipx, runner: CommandRunner()) == .found("pipx 1.17.10"))

        let uv = try script(home, "#!/bin/sh\ncat <<'EOF'\n\(try Fixture.text("uv-version.txt"))EOF\n")
        #expect(await PathValidation.pythonManager(.uv, path: uv, runner: CommandRunner()) == .found("uv 0.12.22 (70fe1196a 2026-10-01 aarch64-apple-darwin)"))
    }

    @Test func rejectsAProgramThatIsTheOtherManager() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let uv = try script(home, "#!/bin/sh\necho 'uv 0.12.22'\n")

        #expect(await PathValidation.pythonManager(.pipx, path: uv, runner: CommandRunner()) == .problem("This program did not run as pipx."))
    }

    @Test func explainsAPathThatDoesNotExist() async {
        #expect(await PathValidation.pythonManager(.uv, path: "/nonexistent/uv", runner: CommandRunner()) == .problem("Nothing was found at this path."))
    }
}
