import Foundation
import Testing
@testable import DevHubCore

private func subject(_ name: String, bucket: Bucket, kind: PackageKind, group: String? = nil) -> InstalledPackage {
    InstalledPackage(bucket: bucket, kind: kind, name: name, group: group, installedVersion: "")
}

@Suite struct NewestVersionParserTests {
    @Test func readsTheStableVersionOfAFormula() throws {
        #expect(BrewParser.parseNewestVersion(try Fixture.data("brew-info-formula-jq.json")) == "1.8.2")
    }

    @Test func readsTheVersionOfACask() throws {
        #expect(BrewParser.parseNewestVersion(try Fixture.data("brew-info-cask-raycast.json")) == "2.6.2.0")
    }

    @Test func readsNothingFromOutputThatIsNotBrewJSON() {
        #expect(BrewParser.parseNewestVersion(Data("Error: nope".utf8)) == nil)
        #expect(BrewParser.parseNewestVersion(Data(#"{"formulae":[],"casks":[]}"#.utf8)) == nil)
    }

    @Test func readsTheNewestGemFromTheRemoteList() throws {
        #expect(GemParser.parseRemoteVersion(of: "rails", in: try Fixture.text("gem-remote-rails.txt")) == "8.1.4")
        #expect(GemParser.parseRemoteVersion(of: "rails", in: try Fixture.text("gem-remote-missing.txt")) == nil)
    }

    @Test func aRemoteListEntryMustMatchTheNameExactly() {
        #expect(GemParser.parseRemoteVersion(of: "rails", in: "rails-html-sanitizer (1.6.0)\nrails (8.0.0)") == "8.0.0")
        #expect(GemParser.parseRemoteVersion(of: "rail", in: "rails (8.0.0)") == nil)
    }

    @Test func readsTheNewestVersionFromPipIndex() throws {
        #expect(PythonParser.parsePipIndexNewest(try Fixture.text("pip-index-black.txt")) == "26.5.1")
        #expect(PythonParser.parsePipIndexNewest("") == nil)
        #expect(PythonParser.parsePipIndexNewest("ERROR: No matching distribution found") == nil)
    }

    @Test(arguments: ["stable", "beta", "nightly", "1.85.0", "1.85", "nightly-2026-09-01", "stable-aarch64-apple-darwin", "1.85.0-x86_64-unknown-linux-gnu"])
    func acceptsToolchainNames(name: String) {
        #expect(RustupParser.isToolchainName(name))
    }

    @Test(arguments: ["", "unstable", "my custom", "--stable", "stable;rm", "latest"])
    func rejectsNamesThatAreNotToolchains(name: String) {
        #expect(!RustupParser.isToolchainName(name))
    }
}

@Suite struct ResolveInstallTests {
    private let brew = HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew"))

    private func homebrew(_ handler: @escaping @Sendable (ToolCommand) -> CommandResult) -> (HomebrewScanner, FakeRunner) {
        let fake = FakeRunner(handler)
        return (HomebrewScanner(installation: brew, runner: fake), fake)
    }

    @Test func homebrewFindsAFormulaAndACask() async throws {
        let formulaJSON = try Fixture.text("brew-info-formula-jq.json"), caskJSON = try Fixture.text("brew-info-cask-raycast.json")
        let (scanner, fake) = homebrew { command in succeeded(command.arguments.contains("--cask") ? caskJSON : formulaJSON) }

        let formula = await scanner.resolveInstall(of: subject("jq", bucket: .homebrew, kind: .formula))
        let cask = await scanner.resolveInstall(of: subject("raycast", bucket: .homebrew, kind: .cask))

        #expect(formula == .current(version: "1.8.2"))
        #expect(cask == .current(version: "2.6.2.0"))
        #expect(fake.commands.map(\.arguments) == [["info", "--formula", "--json=v2", "jq"], ["info", "--cask", "--json=v2", "raycast"]])
    }

    @Test func homebrewReportsAMissingFormulaAndCask() async throws {
        let formulaError = try Fixture.text("brew-info-missing-formula.stderr.txt"), caskError = try Fixture.text("brew-info-missing-cask.stderr.txt")
        let (scanner, _) = homebrew { command in failed(exitCode: 1, standardError: command.arguments.contains("--cask") ? caskError : formulaError) }

        #expect(await scanner.resolveInstall(of: subject("x", bucket: .homebrew, kind: .formula)) == .notFound)
        #expect(await scanner.resolveInstall(of: subject("x", bucket: .homebrew, kind: .cask)) == .notFound)
    }

    @Test func homebrewTreatsOtherFailuresAsUnavailable() async {
        let (scanner, _) = homebrew { _ in failed(exitCode: 1, standardError: "Error: Failed to download") }

        #expect(await scanner.resolveInstall(of: subject("jq", bucket: .homebrew, kind: .formula)) == .unavailable)
        #expect(await scanner.resolveInstall(of: subject("rake", bucket: .ruby, kind: .gem, group: "3.4.1")) == nil)
    }

    private let ruby = RubyInstallation(version: "3.4.1", manager: .rbenv, root: URL(filePath: "/home/.rbenv/versions/3.4.1"))

    @Test func rubyFindsTheNewestGem() async throws {
        let remote = try Fixture.text("gem-remote-rails.txt")
        let fake = FakeRunner { _ in succeeded(remote) }
        let scanner = RubyScanner(installations: [ruby], runner: fake)

        let resolution = await scanner.resolveInstall(of: subject("rails", bucket: .ruby, kind: .gem, group: "3.4.1"))

        #expect(resolution == .current(version: "8.1.4"))
        #expect(fake.commands.first?.arguments == ["list", "--remote", "--exact", "rails"])
    }

    @Test func rubyReportsAMissingGemAndAFailedLookup() async throws {
        let missing = RubyScanner(installations: [ruby], runner: FakeRunner { _ in succeeded(try! Fixture.text("gem-remote-missing.txt")) })
        let offline = RubyScanner(installations: [ruby], runner: FakeRunner { _ in failed(exitCode: 2, standardError: "ERROR: Could not reach rubygems.org") })
        let package = subject("nope", bucket: .ruby, kind: .gem, group: "3.4.1")

        #expect(await missing.resolveInstall(of: package) == .notFound)
        #expect(await offline.resolveInstall(of: package) == .unavailable)
        #expect(await missing.resolveInstall(of: subject("nope", bucket: .ruby, kind: .gem, group: "2.7.0")) == nil)
    }

    private let rustup = URL(filePath: "/home/.cargo/bin/rustup")
    private let cargo = URL(filePath: "/home/.cargo/bin/cargo")

    @Test func rustFindsACargoToolOnCratesIO() async throws {
        let search = try Fixture.text("cargo-search-hexyl.txt")
        let fake = FakeRunner { _ in succeeded(search) }
        let scanner = RustScanner(installation: RustInstallation(rustup: rustup, cargo: cargo), runner: fake)

        #expect(await scanner.resolveInstall(of: subject("hexyl", bucket: .rust, kind: .cargoTool)) == .current(version: "0.17.0"))
        #expect(fake.commands.first?.arguments == ["search", "hexyl", "--limit", "10"])
    }

    @Test func rustReportsAMissingCrateAndAFailedSearch() async throws {
        let empty = try Fixture.text("cargo-search-missing.txt")
        let missing = RustScanner(installation: RustInstallation(rustup: rustup, cargo: cargo), runner: FakeRunner { _ in succeeded(empty) })
        let offline = RustScanner(installation: RustInstallation(rustup: rustup, cargo: cargo), runner: FakeRunner { _ in failed(exitCode: 101, standardError: "error: failed to query") })
        let noCargo = RustScanner(installation: RustInstallation(rustup: rustup, cargo: nil), runner: FakeRunner { _ in succeeded("") })
        let crate = subject("cargo-typo", bucket: .rust, kind: .cargoTool)

        #expect(await missing.resolveInstall(of: crate) == .notFound)
        #expect(await offline.resolveInstall(of: crate) == .unavailable)
        #expect(await noCargo.resolveInstall(of: crate) == .unavailable)
    }

    @Test func rustChecksToolchainNamesWithoutRunningAnything() async {
        let fake = FakeRunner { _ in succeeded("") }
        let scanner = RustScanner(installation: RustInstallation(rustup: rustup, cargo: cargo), runner: fake)

        #expect(await scanner.resolveInstall(of: subject("nightly", bucket: .rust, kind: .rustToolchain)) == .current(version: "nightly"))
        #expect(await scanner.resolveInstall(of: subject("latest", bucket: .rust, kind: .rustToolchain)) == .notFound)
        #expect(await scanner.resolveInstall(of: subject("rustup", bucket: .rust, kind: .rustToolchain)) == nil)
        #expect(fake.commands.isEmpty)
    }

    private let pipx = PythonInstallation(manager: .pipx, executable: URL(filePath: "/home/.local/bin/pipx"))
    private let uv = PythonInstallation(manager: .uv, executable: URL(filePath: "/home/.local/bin/uv"))

    @Test func pythonRunsPipIndexThroughEachManager() async throws {
        let index = try Fixture.text("pip-index-black.txt")
        let fake = FakeRunner { _ in succeeded(index) }
        let scanner = PythonScanner(installations: [pipx, uv], runner: fake)

        let viaPipx = await scanner.resolveInstall(of: subject("black", bucket: .python, kind: .pythonTool, group: "pipx"))
        let viaUv = await scanner.resolveInstall(of: subject("black", bucket: .python, kind: .pythonTool, group: "uv"))

        #expect(viaPipx == .current(version: "26.5.1"))
        #expect(viaUv == .current(version: "26.5.1"))
        #expect(fake.commands.map(\.arguments) == [["run", "pip", "index", "versions", "black"], ["tool", "run", "pip", "index", "versions", "black"]])
    }

    @Test func pythonReportsAMissingPackageAndAFailedLookup() async throws {
        let stderr = try Fixture.text("pip-index-missing.stderr.txt")
        let missing = PythonScanner(installations: [uv], runner: FakeRunner { _ in failed(exitCode: 1, standardError: stderr) })
        let offline = PythonScanner(installations: [uv], runner: FakeRunner { _ in failed(exitCode: 1, standardError: "WARNING: Retrying after connection broken") })
        let package = subject("pythn-typo", bucket: .python, kind: .pythonTool, group: "uv")

        #expect(await missing.resolveInstall(of: package) == .notFound)
        #expect(await offline.resolveInstall(of: package) == .unavailable)
        #expect(await missing.resolveInstall(of: subject("black", bucket: .python, kind: .pythonTool, group: "pipx")) == nil)
    }
}
