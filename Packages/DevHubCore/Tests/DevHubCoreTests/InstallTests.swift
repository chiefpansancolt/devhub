import Foundation
import Testing
@testable import DevHubCore

private func toInstall(_ name: String, bucket: Bucket = .node, kind: PackageKind = .npmGlobal, group: String? = nil, version: String? = nil) -> InstalledPackage {
    InstalledPackage(bucket: bucket, kind: kind, name: name, group: group, installedVersion: "", availableUpdate: version)
}

@Suite struct InstallCommandTests {
    @Test func homebrewInstallsFormulaeAndCasks() throws {
        let scanner = HomebrewScanner(installation: HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew")), runner: FakeRunner { _ in succeeded("") })

        #expect(scanner.installCommand(for: toInstall("git", bucket: .homebrew, kind: .formula))?.arguments == ["install", "git"])
        #expect(scanner.installCommand(for: toInstall("raycast", bucket: .homebrew, kind: .cask))?.arguments == ["install", "--cask", "raycast"])
        #expect(scanner.installCommand(for: toInstall("rake", bucket: .ruby, kind: .gem, group: "3.3.5")) == nil)
    }

    private let node = NodeInstallation(version: "26.1.0", manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v26.1.0"))

    @Test func npmInstallsTheExactVersionIntoTheNodeVersion() throws {
        let scanner = NodeScanner(installations: [node], runner: FakeRunner { _ in succeeded("") })

        let pinned = try #require(scanner.installCommand(for: toInstall("prettier", group: "26.1.0", version: "3.3.3")))
        let newest = try #require(scanner.installCommand(for: toInstall("serve", group: "26.1.0")))

        #expect(pinned.arguments == ["install", "-g", "prettier@3.3.3"])
        #expect(pinned.executable == node.npm)
        #expect(pinned.context == "Node 26.1.0")
        #expect(newest.arguments == ["install", "-g", "serve@latest"])
        #expect(scanner.installCommand(for: toInstall("serve", group: "20.0.0")) == nil)
    }

    @Test func gemInstallsIntoTheRubyVersionWithoutDocumentationByDefault() throws {
        let ruby = RubyInstallation(version: "3.4.1", manager: .rbenv, root: URL(filePath: "/home/.rbenv/versions/3.4.1"))
        let plain = RubyScanner(installations: [ruby], runner: FakeRunner { _ in succeeded("") })
        let documented = RubyScanner(installations: [ruby], runner: FakeRunner { _ in succeeded("") }, options: RubyOptions(installDocumentation: true))
        let package = toInstall("rails", bucket: .ruby, kind: .gem, group: "3.4.1")

        #expect(plain.installCommand(for: package)?.arguments == ["install", "rails", "--no-document"])
        #expect(documented.installCommand(for: package)?.arguments == ["install", "rails"])
        #expect(plain.installCommand(for: toInstall("rails", bucket: .ruby, kind: .gem, group: "3.4.1", version: "7.1.3"))?.arguments == ["install", "rails", "--version", "7.1.3", "--no-document"])
        #expect(plain.installCommand(for: toInstall("rails", bucket: .ruby, kind: .gem, group: "2.7.0")) == nil)
    }

    @Test func rustInstallsToolchainsAndCargoTools() {
        let installation = RustInstallation(rustup: URL(filePath: "/home/.cargo/bin/rustup"), cargo: URL(filePath: "/home/.cargo/bin/cargo"))
        let scanner = RustScanner(installation: installation, runner: FakeRunner { _ in succeeded("") })

        #expect(scanner.installCommand(for: toInstall("nightly", bucket: .rust, kind: .rustToolchain))?.arguments == ["toolchain", "install", "nightly", "--no-self-update"])
        #expect(scanner.installCommand(for: toInstall("hexyl", bucket: .rust, kind: .cargoTool))?.arguments == ["install", "--locked", "hexyl"])
        #expect(scanner.installCommand(for: toInstall("hexyl", bucket: .rust, kind: .cargoTool, version: "0.17.0"))?.arguments == ["install", "--locked", "--version", "0.17.0", "hexyl"])
        #expect(scanner.installCommand(for: toInstall("rustup", bucket: .rust, kind: .rustToolchain)) == nil)
    }

    @Test func rustHasNoCargoToolInstallWithoutCargo() {
        let installation = RustInstallation(rustup: URL(filePath: "/home/.cargo/bin/rustup"), cargo: nil)
        let scanner = RustScanner(installation: installation, runner: FakeRunner { _ in succeeded("") })

        #expect(scanner.installCommand(for: toInstall("hexyl", bucket: .rust, kind: .cargoTool)) == nil)
    }

    @Test func pythonInstallsWithEachManager() {
        let pipx = PythonInstallation(manager: .pipx, executable: URL(filePath: "/home/.local/bin/pipx"))
        let uv = PythonInstallation(manager: .uv, executable: URL(filePath: "/home/.local/bin/uv"))
        let scanner = PythonScanner(installations: [pipx, uv], runner: FakeRunner { _ in succeeded("") })

        #expect(scanner.installCommand(for: toInstall("black", bucket: .python, kind: .pythonTool, group: "pipx"))?.arguments == ["install", "black"])
        #expect(scanner.installCommand(for: toInstall("ruff", bucket: .python, kind: .pythonTool, group: "uv", version: "0.5.0"))?.arguments == ["tool", "install", "ruff==0.5.0"])
        #expect(scanner.installCommand(for: toInstall("ruff", bucket: .python, kind: .pythonTool, group: "poetry")) == nil)
    }

    @Test func pnpmBunAndYarnInstallByName() {
        let installations = [
            NodePackageManagerInstallation(manager: .pnpm, executable: URL(filePath: "/home/pnpm")),
            NodePackageManagerInstallation(manager: .bun, executable: URL(filePath: "/home/bun")),
            NodePackageManagerInstallation(manager: .yarn, executable: URL(filePath: "/home/yarn"))
        ]
        let scanner = NodeToolsScanner(installations: installations, runner: FakeRunner { _ in succeeded("") })

        #expect(scanner.installCommand(for: toInstall("cowsay", kind: .pnpmGlobal, group: "pnpm", version: "1.6.0"))?.arguments == ["add", "-g", "cowsay@1.6.0"])
        #expect(scanner.installCommand(for: toInstall("cowsay", kind: .bunGlobal, group: "Bun"))?.arguments == ["add", "-g", "cowsay@latest"])
        #expect(scanner.installCommand(for: toInstall("cowsay", kind: .yarnGlobal, group: "Yarn", version: "1.6.0"))?.arguments == ["global", "add", "cowsay@1.6.0"])
    }

    @Test func theCombinedScannerAsksEachScanner() {
        let npm = NodeScanner(installations: [node], runner: FakeRunner { _ in succeeded("") })
        let tools = NodeToolsScanner(installations: [NodePackageManagerInstallation(manager: .pnpm, executable: URL(filePath: "/home/pnpm"))], runner: FakeRunner { _ in succeeded("") })
        let combined = CombinedScanner(bucket: .node, scanners: [npm, tools])

        #expect(combined.installCommand(for: toInstall("serve", group: "26.1.0"))?.executable == node.npm)
        #expect(combined.installCommand(for: toInstall("cowsay", kind: .pnpmGlobal, group: "pnpm"))?.executable.lastPathComponent == "pnpm")
        #expect(combined.installCommand(for: toInstall("cowsay", kind: .yarnGlobal, group: "Yarn")) == nil)
    }

    @Test func aScannerWithoutInstallSupportReturnsNothing() {
        struct Plain: PackageScanner {
            let bucket = Bucket.homebrew
            func scan(_ reason: ScanReason) async -> ScanResult { ScanResult(packages: []) }
            func updateCommand(for package: InstalledPackage) -> ToolCommand? { nil }
            func uninstallCommand(for package: InstalledPackage) -> ToolCommand? { nil }
        }

        #expect(Plain().installCommand(for: toInstall("git", bucket: .homebrew, kind: .formula)) == nil)
    }
}

private struct OrderScanner: PackageScanner {
    let bucket: Bucket

    func scan(_ reason: ScanReason) async -> ScanResult { ScanResult(packages: []) }
    func updateCommand(for package: InstalledPackage) -> ToolCommand? { nil }
    func uninstallCommand(for package: InstalledPackage) -> ToolCommand? { nil }
    func installCommand(for package: InstalledPackage) -> ToolCommand? {
        ToolCommand(executable: URL(filePath: "/usr/bin/\(bucket.rawValue)"), arguments: ["install", package.name], environment: [:])
    }
}

@MainActor
@Suite struct InstallEngineTests {
    private func state(_ machine: FakeMachine, buckets: [Bucket] = [.node]) -> AppState {
        AppState(scanners: Dictionary(uniqueKeysWithValues: buckets.map { ($0, FakeScanner(bucket: $0, machine: machine) as any PackageScanner) }), runner: machine.runner, history: HistoryStore())
    }

    @Test func installingRunsTheInstallCommandAndRecordsAnInstallInHistory() async throws {
        let machine = FakeMachine(packages: [])
        let app = state(machine)

        await app.install([toInstall("prettier", group: "26.1.0", version: "3.3.3"), toInstall("serve", group: "26.1.0")])

        #expect(machine.installedNames == ["prettier", "serve"])
        let entries = app.history.entries.filter { $0.action == .install }
        #expect(entries.count == 2)
        let first = try #require(entries.first { $0.package == "prettier" })
        #expect(first.ok)
        #expect(first.fromVersion == nil)
        #expect(first.toVersion == "3.3.3")
        #expect(first.group == "26.1.0")
        #expect(app.session == nil)
    }

    @Test func aFailedInstallKeepsTheSessionAndRetryRunsInstallAgain() async {
        let machine = FakeMachine(packages: [], failing: ["vercel"])
        let app = state(machine)

        await app.install([toInstall("vercel", group: "26.1.0"), toInstall("serve", group: "26.1.0")])

        #expect(app.session?.action == .install)
        #expect(app.session?.failedCount == 1)
        #expect(machine.installedNames == ["serve"])

        app.retryFailed()
        await waitUntil { app.session?.isRunning == false && app.history.entries.filter { $0.action == .install }.count == 3 }

        #expect(app.history.entries.filter { $0.action == .install }.count == 3)
        #expect(app.history.entries.filter { $0.action == .update }.isEmpty)
        #expect(app.session?.action == .install)
    }

    @Test func aPackageWithNoInstallCommandFails() async {
        let package = toInstall("serve", bucket: .ruby, kind: .gem, group: "3.4.1")
        let runner = PackageActionRunner(scanners: [:], runner: FakeRunner { _ in succeeded("") })

        let outcomes = await runner.install([package]) { _ in }

        #expect(outcomes[0].status == .failed("DevHub has no way to install this package."))
        #expect(outcomes[0].command == nil)
    }

    @Test func homebrewFinishesBeforeTheOtherToolsStart() async {
        let packages = [toInstall("serve", group: "26.1.0"), toInstall("git", bucket: .homebrew, kind: .formula), toInstall("rails", bucket: .ruby, kind: .gem, group: "3.4.1")]
        let fake = FakeRunner { _ in succeeded("") }
        let runner = PackageActionRunner(scanners: [.homebrew: OrderScanner(bucket: .homebrew), .node: OrderScanner(bucket: .node), .ruby: OrderScanner(bucket: .ruby)], runner: fake)

        let outcomes = await runner.install(packages) { _ in }

        #expect(fake.commands.first?.executable.lastPathComponent == "homebrew")
        #expect(Set(fake.commands.map { $0.executable.lastPathComponent }) == ["homebrew", "node", "ruby"])
        #expect(outcomes.map(\.package.name) == ["serve", "git", "rails"])
    }

    @Test func installsInsideOneToolKeepTheGivenOrder() async {
        let packages = ["a", "b", "c", "d"].map { toInstall($0, group: "26.1.0") }
        let fake = FakeRunner { _ in succeeded("") }
        let runner = PackageActionRunner(scanners: [.node: OrderScanner(bucket: .node)], runner: fake)

        _ = await runner.install(packages) { _ in }

        #expect(fake.commands.map { $0.arguments.last } == ["a", "b", "c", "d"])
    }

    @Test func cancellingAnInstallMarksTheRestSkipped() async {
        let packages = [toInstall("a", group: "26.1.0"), toInstall("b", group: "26.1.0")]
        let machine = FakeMachine(packages: [])
        let hanging = PackageActionRunner(scanners: [.node: FakeScanner(bucket: .node, machine: machine)], runner: HangingRunner())

        let task = Task { await hanging.install(packages) { _ in } }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let outcomes = await task.value

        #expect(outcomes.map(\.status) == [.skipped, .skipped])
    }
}

@Suite struct InstallHistoryTests {
    @Test func installIsAnActionTheLogCanRead() throws {
        let line = Data(#"{"action":"install","bucket":"node","command":"npm install -g serve@14.2.4","durationMs":5,"exitCode":0,"id":"5E8F2C1A-0B0C-4D8E-9E55-1F0E3F2A7B11","ok":true,"package":"serve","timestamp":"2026-10-02T10:42:00.000-04:00","trigger":"manual"}"#.utf8)

        let entry = try HistoryCoding.decoder().decode(HistoryEntry.self, from: line)

        #expect(entry.action == .install)
        #expect(HistoryAction.allCases.map(\.rawValue) == ["check", "update", "uninstall", "install"])
    }

    @Test func theInstallsFilterKeepsOnlyInstalls() {
        func entry(_ action: HistoryAction) -> HistoryEntry {
            HistoryEntry(timestamp: Date(), action: action, bucket: .node, package: "x", group: nil, fromVersion: nil, toVersion: nil, trigger: .manual, command: "", exitCode: 0, durationMs: 0, ok: true, message: nil, output: nil)
        }

        let kept = HistoryListing.filter([entry(.install), entry(.update), entry(.uninstall)], action: .installs, range: .allTime, bucket: nil, search: "", now: Date())

        #expect(kept.map(\.action) == [.install])
    }
}
