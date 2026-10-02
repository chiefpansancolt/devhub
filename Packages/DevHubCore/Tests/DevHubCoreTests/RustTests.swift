import Foundation
import Testing
@testable import DevHubCore

@Suite struct RustupParserTests {
    @Test func readsTheRealToolchainList() throws {
        let toolchains = RustupParser.parseToolchains(try Fixture.text("rustup-toolchain-list.txt"))

        #expect(toolchains == [
            RustupParser.InstalledToolchain(
                name: "stable-aarch64-apple-darwin",
                path: "/Users/example/.rustup/toolchains/stable-aarch64-apple-darwin"
            )
        ])
    }

    @Test func readsToolchainsWithAndWithoutFlags() throws {
        let toolchains = RustupParser.parseToolchains(try Fixture.text("rustup-toolchain-list.synthetic.txt"))

        #expect(toolchains.map(\.name) == [
            "stable-aarch64-apple-darwin", "nightly-aarch64-apple-darwin", "1.85.0-aarch64-apple-darwin", "my-custom"
        ])
        #expect(toolchains[1].path == "/Users/example/.rustup/toolchains/nightly-aarch64-apple-darwin")
        #expect(toolchains[3].path == "/Users/example/Code/rust/build/stage1")
    }

    @Test func readsAnUpdateAndTheVersionThatIsInstalled() throws {
        let statuses = RustupParser.parseCheck(try Fixture.text("rustup-check-update-available.txt"))

        #expect(statuses == [
            RustupParser.ToolchainStatus(name: "stable-aarch64-apple-darwin", installedVersion: "1.98.1", availableVersion: "1.99.0"),
            RustupParser.ToolchainStatus(name: "rustup", installedVersion: "1.29.1", availableVersion: nil)
        ])
    }

    @Test func readsEveryFormOfTheCheckLine() throws {
        let statuses = RustupParser.parseCheck(try Fixture.text("rustup-check.synthetic.txt"))

        #expect(statuses.map(\.name) == [
            "stable-aarch64-apple-darwin", "beta-aarch64-apple-darwin", "nightly-aarch64-apple-darwin",
            "1.85.0-aarch64-apple-darwin", "rustup"
        ])
        #expect(statuses[0].availableVersion == nil)
        #expect(statuses[1].installedVersion == "1.100.0-beta.1")
        #expect(statuses[1].availableVersion == "1.100.0-beta.2")
        #expect(statuses[2].installedVersion == "1.101.0-nightly")
        #expect(statuses[3].installedVersion == "1.85.0")
        #expect(statuses[4].availableVersion == "1.30.0")
    }

    @Test func ignoresLinesThatAreNotStatuses() {
        let text = "info: checking for self-update\nstable - error: could not read the toolchain\n"

        #expect(RustupParser.parseCheck(text).isEmpty)
    }

    @Test func readsTheCompilerVersion() {
        #expect(RustupParser.parseCompilerVersion("rustc 1.98.1 (48a229cea 2026-09-01)\n") == "1.98.1")
        #expect(RustupParser.parseCompilerVersion("error: toolchain is not installed") == nil)
    }
}

@Suite struct CargoParserTests {
    @Test func readsTheRealList() throws {
        let tools = CargoParser.parseInstalled(try Fixture.text("cargo-install-list.txt"))

        #expect(tools == [CargoParser.InstalledTool(name: "hexyl", version: "0.9.0", isFromRegistry: true)])
    }

    @Test func tellsRegistryToolsFromGitAndFolderTools() throws {
        let tools = CargoParser.parseInstalled(try Fixture.text("cargo-install-list.synthetic.txt"))

        #expect(tools.map(\.name) == ["cargo-update", "from-git", "hexyl", "local-tool", "ripgrep"])
        #expect(tools.map(\.isFromRegistry) == [true, false, true, false, true])
        #expect(tools.first { $0.name == "ripgrep" }?.version == "14.1.1")
    }

    @Test func readsNothingFromAnEmptyList() {
        #expect(CargoParser.parseInstalled("").isEmpty)
    }

    @Test func findsTheExactNameInTheSearchResults() throws {
        let text = try Fixture.text("cargo-search-hexyl.txt")

        #expect(CargoParser.parseLatestVersion(of: "hexyl", in: text) == "0.17.0")
        #expect(CargoParser.parseLatestVersion(of: "hextazy", in: text) == "0.8.6")
    }

    @Test func ignoresNearMatchesAndTheTrailingLine() throws {
        let text = try Fixture.text("cargo-search-hexyl.txt")

        #expect(CargoParser.parseLatestVersion(of: "hex", in: text) == nil)
        #expect(CargoParser.parseLatestVersion(of: "crates", in: text) == nil)
    }
}

@Suite struct RustLocatorTests {
    @Test func findsRustupInCargoAndTheCargoNextToIt() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".cargo/bin/rustup")
        try home.makeExecutable(".cargo/bin/cargo")

        let installation = try #require(RustLocator.locate(home: home.url))

        #expect(installation.rustup == home.url.appending(path: ".cargo/bin/rustup"))
        #expect(installation.cargo == home.url.appending(path: ".cargo/bin/cargo"))
        #expect(installation.binDirectory.path == home.url.appending(path: ".cargo/bin").path)
    }

    @Test func worksWithoutCargo() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".cargo/bin/rustup")

        #expect(try #require(RustLocator.locate(home: home.url)).cargo == nil)
    }

    @Test func findsNothingWithoutRustup() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".cargo/bin/cargo")

        #expect(RustLocator.locate(home: home.url) == nil)
    }
}

@Suite struct RustScannerTests {
    private let installation = RustInstallation(
        rustup: URL(filePath: "/home/.cargo/bin/rustup"),
        cargo: URL(filePath: "/home/.cargo/bin/cargo")
    )

    private func runner(
        check: CommandResult? = nil,
        cargoList: String? = nil,
        search: @escaping @Sendable (String) -> CommandResult = { _ in failed(exitCode: 101, standardError: "error") }
    ) -> FakeRunner {
        FakeRunner { command in
            let name = command.executable.lastPathComponent
            let arguments = command.arguments
            switch (name, arguments.first) {
            case ("rustup", "toolchain"):
                return succeeded((try? Fixture.text("rustup-toolchain-list.txt")) ?? "")
            case ("rustup", "check"):
                return check ?? CommandResult(exitCode: 100, standardOutput: (try? Fixture.text("rustup-check-update-available.txt")) ?? "", standardError: "")
            case ("rustup", "run"):
                return succeeded("rustc 1.98.1 (48a229cea 2026-09-01)")
            case ("cargo", "install"):
                return succeeded(cargoList ?? (try? Fixture.text("cargo-install-list.txt")) ?? "")
            case ("cargo", "search"):
                return search(arguments[1])
            default:
                return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    private let hexylSearch: @Sendable (String) -> CommandResult = { name in
        succeeded(name == "hexyl" ? "hexyl = \"0.17.0\"    # A command-line hex viewer\n" : "")
    }

    @Test func listsTheToolchainsAndRustupWithTheirUpdates() async throws {
        let result = await RustScanner(installation: installation, runner: runner(search: hexylSearch)).scan()

        #expect(result.issues.isEmpty)
        let stable = try #require(result.packages.first { $0.name == "stable-aarch64-apple-darwin" })
        #expect(stable.kind == .rustToolchain)
        #expect(stable.installedVersion == "1.98.1")
        #expect(stable.availableUpdate == "1.99.0")
        #expect(stable.installPath == "/Users/example/.rustup/toolchains/stable-aarch64-apple-darwin")
        let rustup = try #require(result.packages.first { $0.name == "rustup" })
        #expect(rustup.installedVersion == "1.29.1")
        #expect(rustup.isOutdated == false)
    }

    @Test func treatsExitCodeOneHundredFromCheckAsSuccess() async {
        let result = await RustScanner(installation: installation, runner: runner(search: hexylSearch)).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.contains { $0.isOutdated })
    }

    @Test func listsCargoToolsWithTheNewestVersionFromTheRegistry() async throws {
        let result = await RustScanner(installation: installation, runner: runner(search: hexylSearch)).scan()

        let hexyl = try #require(result.packages.first { $0.name == "hexyl" })
        #expect(hexyl.kind == .cargoTool)
        #expect(hexyl.installedVersion == "0.9.0")
        #expect(hexyl.availableUpdate == "0.17.0")
        #expect(hexyl.homepage == "https://crates.io/crates/hexyl")
    }

    @Test func doesNotLookUpToolsThatCameFromGitOrAFolder() async throws {
        let fake = runner(cargoList: try Fixture.text("cargo-install-list.synthetic.txt"), search: hexylSearch)

        let result = await RustScanner(installation: installation, runner: fake).scan()

        let searched = fake.commands.filter { $0.arguments.first == "search" }.map { $0.arguments[1] }
        #expect(Set(searched) == ["cargo-update", "hexyl", "ripgrep"])
        #expect(result.packages.first { $0.name == "from-git" }?.availableUpdate == nil)
        #expect(result.packages.first { $0.name == "local-tool" }?.homepage == nil)
    }

    @Test func aToolWhoseLookupFailsStaysListedWithoutAnUpdate() async throws {
        let result = await RustScanner(installation: installation, runner: runner()).scan()

        let hexyl = try #require(result.packages.first { $0.name == "hexyl" })
        #expect(hexyl.isOutdated == false)
        #expect(result.issues.isEmpty)
    }

    @Test func skipsCargoToolsWhenTheOptionIsOff() async {
        let fake = runner(search: hexylSearch)

        let result = await RustScanner(installation: installation, runner: fake, options: RustOptions(includeCargoTools: false)).scan()

        #expect(result.packages.allSatisfy { $0.kind == .rustToolchain })
        #expect(!fake.commands.contains { $0.executable.lastPathComponent == "cargo" })
    }

    @Test func skipsCargoToolsWhenThereIsNoCargo() async {
        let noCargo = RustInstallation(rustup: installation.rustup, cargo: nil)

        let result = await RustScanner(installation: noCargo, runner: runner(search: hexylSearch)).scan()

        #expect(result.packages.allSatisfy { $0.kind == .rustToolchain })
        #expect(result.issues.isEmpty)
    }

    @Test func keepsTheToolchainsWhenTheCheckFails() async throws {
        let offline = failed(exitCode: 1, standardError: "error: could not download file")

        let result = await RustScanner(installation: installation, runner: runner(check: offline, search: hexylSearch)).scan()

        let stable = try #require(result.packages.first { $0.name == "stable-aarch64-apple-darwin" })
        #expect(stable.installedVersion == "1.98.1")
        #expect(stable.isOutdated == false)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.message.contains("rustup check") == true)
    }

    @Test func reportsAnIssueWhenTheToolchainListFails() async {
        let broken = FakeRunner { command in
            command.arguments.first == "toolchain" ? failed(exitCode: 1, standardError: "error: rustup is broken") : succeeded("")
        }

        let result = await RustScanner(installation: installation, runner: broken, options: RustOptions(includeCargoTools: false)).scan()

        #expect(result.packages.isEmpty)
        #expect(result.issues.count == 1)
    }

    private func package(_ name: String, _ kind: PackageKind) -> InstalledPackage {
        InstalledPackage(bucket: .rust, kind: kind, name: name, installedVersion: "1.0.0", availableUpdate: "2.0.0")
    }

    @Test func buildsTheUpdateCommands() {
        let scanner = RustScanner(installation: installation, runner: runner())

        #expect(scanner.updateCommand(for: package("stable-aarch64-apple-darwin", .rustToolchain))?.arguments == ["update", "stable-aarch64-apple-darwin", "--no-self-update"])
        #expect(scanner.updateCommand(for: package("rustup", .rustToolchain))?.arguments == ["self", "update"])
        #expect(scanner.updateCommand(for: package("hexyl", .cargoTool))?.arguments == ["install", "--locked", "hexyl"])
        #expect(scanner.updateCommand(for: package("hexyl", .cargoTool))?.executable == installation.cargo)
    }

    @Test func buildsTheUninstallCommandsAndNeverRemovesRustupItself() {
        let scanner = RustScanner(installation: installation, runner: runner())

        #expect(scanner.uninstallCommand(for: package("nightly-aarch64-apple-darwin", .rustToolchain))?.arguments == ["toolchain", "uninstall", "nightly-aarch64-apple-darwin"])
        #expect(scanner.uninstallCommand(for: package("hexyl", .cargoTool))?.arguments == ["uninstall", "hexyl"])
        #expect(scanner.uninstallCommand(for: package("rustup", .rustToolchain)) == nil)
    }

    @Test func refusesPackagesOfOtherTools() {
        let scanner = RustScanner(installation: installation, runner: runner())
        let formula = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "1", availableUpdate: "2")

        #expect(scanner.updateCommand(for: formula) == nil)
        #expect(scanner.uninstallCommand(for: formula) == nil)
    }

    @Test func putsRustupFirstOnThePathAndTurnsColorOff() throws {
        let scanner = RustScanner(installation: installation, runner: runner())

        let command = try #require(scanner.updateCommand(for: package("hexyl", .cargoTool)))

        #expect(command.environment["PATH"]?.hasPrefix("/home/.cargo/bin:") == true)
        #expect(command.environment["NO_COLOR"] == "1")
        #expect(command.environment["CARGO_TERM_COLOR"] == "never")
    }
}

@Suite struct RustScopeTests {
    @Test func splitsRustIntoToolchainsAndCargoTools() {
        let scopes = PackageScope.groups(of: .rust, versions: ["ignored"])

        #expect(scopes.map(\.group) == ["rustToolchain", "cargoTool"])
    }

    @Test func aScopeHoldsOnlyItsKind() {
        let toolchain = InstalledPackage(bucket: .rust, kind: .rustToolchain, name: "stable", installedVersion: "1")
        let tool = InstalledPackage(bucket: .rust, kind: .cargoTool, name: "hexyl", installedVersion: "1")
        let toolchains = PackageScope(bucket: .rust, group: "rustToolchain")

        #expect(toolchains.contains(toolchain))
        #expect(!toolchains.contains(tool))
        #expect(PackageScope(bucket: .rust).contains(tool))
    }
}

@Suite struct RustSettingsTests {
    @Test func rustStartsWithNoChosenPathAndChecksCargoTools() {
        let settings = SettingsValues()

        #expect(settings.rustPath == nil)
        #expect(settings.rustIncludeCargoTools)
    }

    @Test func aSettingsFileFromBeforeRustStillLoads() throws {
        let old = Data(#"{"theme":"dark","brewPath":"/opt/homebrew/bin/brew"}"#.utf8)

        let settings = try JSONDecoder().decode(SettingsValues.self, from: old)

        #expect(settings.theme == .dark)
        #expect(settings.rustPath == nil)
        #expect(settings.rustIncludeCargoTools)
    }

    @Test func changingTheRustSettingsScansAgain() {
        let base = SettingsValues()
        var path = base
        path.rustPath = "/somewhere/rustup"
        var tools = base
        tools.rustIncludeCargoTools = false
        var theme = base
        theme.theme = .dark

        #expect(path.scanningFields != base.scanningFields)
        #expect(tools.scanningFields != base.scanningFields)
        #expect(theme.scanningFields == base.scanningFields)
    }

    @Test func toolchainDetectionHonoursAChosenRustup() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("bin/rustup")
        try home.makeExecutable("bin/cargo")
        var settings = SettingsValues()
        settings.rustPath = home.url.appending(path: "bin/rustup").path

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.rust?.rustup == home.url.appending(path: "bin/rustup"))
        #expect(toolchain.rust?.cargo == home.url.appending(path: "bin/cargo"))
        #expect(toolchain.setupProblems[.rust] == nil)
    }

    @Test func toolchainDetectionExplainsAChosenRustupThatIsMissing() {
        var settings = SettingsValues()
        settings.rustPath = "/nonexistent/bin/rustup"

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.rust == nil)
        #expect(toolchain.setupProblems[.rust] == "There is no rustup program at /nonexistent/bin/rustup.")
    }

    @Test func aRustThatIsOffHasNoInstallationAndNoSetupProblem() {
        var settings = SettingsValues()
        settings.rustPath = "/nonexistent/bin/rustup"
        settings.disabledBuckets = [.rust]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.rust == nil)
        #expect(toolchain.setupProblems[.rust] == nil)
    }
}

@Suite struct RustupPathValidationTests {
    private func script(_ home: TemporaryHome, _ body: String) throws -> String {
        let file = home.url.appending(path: "rustup")
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    @Test func acceptsARealRustup() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let path = try script(home, "#!/bin/sh\necho 'rustup 1.29.1 (d95a37b6a 2026-08-13)'\n")

        let check = await PathValidation.rustup(path: path, runner: CommandRunner())

        #expect(check == .found("rustup 1.29.1 (d95a37b6a 2026-08-13)"))
    }

    @Test func rejectsAProgramThatIsNotRustup() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let path = try script(home, "#!/bin/sh\necho 'something else'\n")

        let check = await PathValidation.rustup(path: path, runner: CommandRunner())

        #expect(check == .problem("This program did not run as rustup."))
    }

    @Test func explainsAPathThatDoesNotExist() async {
        let check = await PathValidation.rustup(path: "/nonexistent/rustup", runner: CommandRunner())

        #expect(check == .problem("Nothing was found at this path."))
    }
}
