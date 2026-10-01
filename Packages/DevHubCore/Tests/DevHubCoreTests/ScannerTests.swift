import Foundation
import Testing
@testable import DevHubCore

@Suite struct HomebrewScannerTests {
    private let installation = HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew"))

    private func runner(updateResult: CommandResult = succeeded("")) -> FakeRunner {
        FakeRunner { command in
            switch command.arguments.first {
            case "update": return updateResult
            case "info": return succeeded((try? Fixture.text("brew-info-installed.json")) ?? "")
            case "outdated": return succeeded((try? Fixture.text("brew-outdated.json")) ?? "")
            default: return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    @Test func combinesTheInstalledListWithTheOutdatedList() async throws {
        let scanner = HomebrewScanner(installation: installation, runner: runner(), options: HomebrewOptions(refreshIndexFirst: false))

        let result = await scanner.scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.count == 8)
        #expect(result.packages.first { $0.name == "git" }?.availableUpdate == "2.56.0")
        #expect(result.packages.first { $0.name == "gettext" }?.availableUpdate == nil)
    }

    @Test func refreshesTheIndexFirstWhenAsked() async {
        let fake = runner()
        let scanner = HomebrewScanner(installation: installation, runner: fake, options: HomebrewOptions(refreshIndexFirst: true))

        _ = await scanner.scan()

        #expect(fake.commands.map { $0.arguments.first } == ["update", "info", "outdated"])
    }

    @Test func doesNotRefreshTheIndexWhenTurnedOff() async {
        let fake = runner()
        let scanner = HomebrewScanner(installation: installation, runner: fake, options: HomebrewOptions(refreshIndexFirst: false))

        _ = await scanner.scan()

        #expect(fake.commands.map { $0.arguments.first } == ["info", "outdated"])
    }

    @Test func aFailedRefreshIsReportedButTheScanContinues() async {
        let fake = runner(updateResult: failed(exitCode: 1, standardError: "Error: Failed to connect to github.com"))
        let scanner = HomebrewScanner(installation: installation, runner: fake, options: HomebrewOptions(refreshIndexFirst: true))

        let result = await scanner.scan()

        #expect(result.packages.count == 8)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].message.contains("Failed to connect to github.com"))
    }

    @Test func aFailedInfoCommandGivesAnIssueAndNoPackages() async {
        let fake = FakeRunner { _ in failed(exitCode: 1, standardError: "Error: broken") }
        let scanner = HomebrewScanner(installation: installation, runner: fake, options: HomebrewOptions(refreshIndexFirst: false))

        let result = await scanner.scan()

        #expect(result.packages.isEmpty)
        #expect(result.issues.map(\.message) == ["brew info --json=v2 --installed exited with code 1: Error: broken"])
    }

    @Test func asksForSelfUpdatingCasksOnlyWhenAsked() async {
        let off = runner()
        _ = await HomebrewScanner(installation: installation, runner: off, options: HomebrewOptions(refreshIndexFirst: false)).scan()
        let on = runner()
        _ = await HomebrewScanner(installation: installation, runner: on, options: HomebrewOptions(refreshIndexFirst: false, includeSelfUpdatingCasks: true)).scan()

        #expect(off.commands.last?.arguments == ["outdated", "--json=v2"])
        #expect(on.commands.last?.arguments == ["outdated", "--json=v2", "--greedy"])
    }

    @Test func buildsUpdateAndUninstallCommands() {
        let scanner = HomebrewScanner(installation: installation, runner: runner())
        let formula = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "2.47.0")
        let cask = InstalledPackage(bucket: .homebrew, kind: .cask, name: "raycast", installedVersion: "1.0")

        #expect(scanner.updateCommand(for: formula)?.arguments == ["upgrade", "git"])
        #expect(scanner.updateCommand(for: cask)?.arguments == ["upgrade", "--cask", "raycast"])
        #expect(scanner.uninstallCommand(for: formula)?.arguments == ["uninstall", "git"])
        #expect(scanner.uninstallCommand(for: cask)?.arguments == ["uninstall", "--cask", "raycast"])
        #expect(scanner.updateCommand(for: formula)?.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    }

    @Test func ignoresPackagesFromOtherBuckets() {
        let scanner = HomebrewScanner(installation: installation, runner: runner())
        let gem = InstalledPackage(bucket: .ruby, kind: .gem, name: "rake", group: "3.3.12", installedVersion: "13.0")

        #expect(scanner.updateCommand(for: gem) == nil)
        #expect(scanner.uninstallCommand(for: gem) == nil)
    }
}

@Suite struct NodeScannerTests {
    private let oldest = NodeInstallation(version: "24.11.1", manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v24.11.1"))
    private let newest = NodeInstallation(version: "25.6.1", manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v25.6.1"))

    /// Answers like npm: `outdated` exits with 1 because it found updates.
    private func npm() -> FakeRunner {
        FakeRunner { command in
            let version = command.executable.path.contains("v25.6.1") ? "v25.6.1" : "v24.11.1"
            switch command.arguments.first {
            case "ls": return succeeded((try? Fixture.text("npm-ls-\(version).json")) ?? "")
            case "outdated":
                return CommandResult(exitCode: 1, standardOutput: (try? Fixture.text("npm-outdated-\(version).json")) ?? "", standardError: "")
            default: return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    @Test func treatsExitCodeOneFromOutdatedAsSuccess() async {
        let result = await NodeScanner(installations: [oldest], runner: npm()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.count == 19)
        #expect(result.packages.filter(\.isOutdated).count == 17)
    }

    @Test func groupsPackagesByNodeVersionNewestFirst() async {
        let result = await NodeScanner(installations: [oldest, newest], runner: npm()).scan()

        #expect(result.packages.first?.group == "25.6.1")
        #expect(result.packages.last?.group == "24.11.1")
        #expect(Set(result.packages.compactMap(\.group)) == ["25.6.1", "24.11.1"])
    }

    @Test func fillsInTheVersionsAndPaths() async throws {
        let result = await NodeScanner(installations: [oldest], runner: npm()).scan()
        let vercel = try #require(result.packages.first { $0.name == "vercel" })

        #expect(vercel.kind == .npmGlobal)
        #expect(vercel.installedVersion == "50.37.3")
        #expect(vercel.availableUpdate == "62.1.0")
        #expect(vercel.installPath == "/home/.nvm/versions/node/v24.11.1/lib/node_modules/vercel")
    }

    @Test func canLeaveNpmItselfOut() async {
        let scanner = NodeScanner(installations: [oldest], runner: npm(), options: NodeOptions(includeNpm: false))

        let result = await scanner.scan()

        #expect(result.packages.contains { $0.name == "npm" } == false)
    }

    @Test func runsEachVersionWithItsOwnNpmFirstInThePath() async throws {
        let fake = npm()

        _ = await NodeScanner(installations: [oldest, newest], runner: fake).scan()

        let forNewest = try #require(fake.commands.first { $0.executable.path.contains("v25.6.1") })
        #expect(forNewest.executable.path == "/home/.nvm/versions/node/v25.6.1/bin/npm")
        #expect(forNewest.environment["PATH"]?.hasPrefix("/home/.nvm/versions/node/v25.6.1/bin:") == true)
        #expect(forNewest.context == "Node 25.6.1")
    }

    @Test func oneBrokenVersionDoesNotHideTheOthers() async {
        let fake = FakeRunner { command in
            if command.executable.path.contains("v25.6.1") { return failed(exitCode: 127, standardError: "node: not found") }
            let isList = command.arguments.first == "ls"
            return succeeded((try? Fixture.text(isList ? "npm-ls-v24.11.1.json" : "npm-outdated-v24.11.1.json")) ?? "")
        }

        let result = await NodeScanner(installations: [oldest, newest], runner: fake).scan()

        #expect(result.packages.count == 19)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].group == "25.6.1")
        #expect(result.issues[0].message.contains("node: not found"))
    }

    @Test func buildsCommandsForThePackagesVersionOnly() {
        let scanner = NodeScanner(installations: [oldest, newest], runner: npm())
        let package = InstalledPackage(bucket: .node, kind: .npmGlobal, name: "typescript", group: "24.11.1", installedVersion: "5.5.4")
        let stranger = InstalledPackage(bucket: .node, kind: .npmGlobal, name: "typescript", group: "18.0.0", installedVersion: "5.5.4")

        #expect(scanner.updateCommand(for: package)?.arguments == ["install", "-g", "typescript@latest"])
        #expect(scanner.updateCommand(for: package)?.executable.path == "/home/.nvm/versions/node/v24.11.1/bin/npm")
        #expect(scanner.uninstallCommand(for: package)?.arguments == ["uninstall", "-g", "typescript"])
        #expect(scanner.updateCommand(for: stranger) == nil)
    }
}

@Suite struct RubyScannerTests {
    private let rvm = RubyInstallation(
        version: "3.3.12",
        manager: .rvm,
        root: URL(filePath: "/home/.rvm/rubies/ruby-3.3.12"),
        gemFolders: [URL(filePath: "/home/.rvm/gems/ruby-3.3.12"), URL(filePath: "/home/.rvm/gems/ruby-3.3.12@global")]
    )
    private let older = RubyInstallation(
        version: "3.1.2",
        manager: .rvm,
        root: URL(filePath: "/home/.rvm/rubies/ruby-3.1.2"),
        gemFolders: [URL(filePath: "/home/.rvm/gems/ruby-3.1.2")]
    )

    private func gem() -> FakeRunner {
        FakeRunner { command in
            let version = command.executable.path.contains("3.1.2") ? "3.1.2" : "3.3.12"
            switch command.arguments.first {
            case "list": return succeeded((try? Fixture.text("gem-list-\(version).txt")) ?? "")
            case "outdated":
                // Broken gem extensions print warnings to standard error on every run.
                return succeeded((try? Fixture.text("gem-outdated-\(version).txt")) ?? "", standardError: "Ignoring bigdecimal-4.1.3 because its extensions are not built.")
            default: return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }

    @Test func combinesTheInstalledListWithTheOutdatedList() async throws {
        let result = await RubyScanner(installations: [rvm], runner: gem()).scan()

        #expect(result.issues.isEmpty)
        #expect(result.packages.count == 128)
        let actionview = try #require(result.packages.first { $0.name == "actionview" })
        #expect(actionview.installedVersion == "8.1.3.1")
        #expect(actionview.availableUpdate == "8.1.4")
        #expect(actionview.group == "3.3.12")
        #expect(result.packages.first { $0.name == "base64" }?.installedVersion == "0.3.0")
    }

    @Test func groupsPackagesByRubyVersionNewestFirst() async {
        let result = await RubyScanner(installations: [older, rvm], runner: gem()).scan()

        #expect(result.packages.first?.group == "3.3.12")
        #expect(result.packages.last?.group == "3.1.2")
    }

    @Test func runsGemWithItsOwnRubyFirstInThePathAndTheGemFolders() async throws {
        let fake = gem()

        _ = await RubyScanner(installations: [rvm], runner: fake).scan()

        let command = try #require(fake.commands.first)
        #expect(command.executable.path == "/home/.rvm/rubies/ruby-3.3.12/bin/gem")
        #expect(command.environment["PATH"]?.hasPrefix("/home/.rvm/rubies/ruby-3.3.12/bin:") == true)
        #expect(command.environment["GEM_HOME"] == "/home/.rvm/gems/ruby-3.3.12")
        #expect(command.environment["GEM_PATH"] == "/home/.rvm/gems/ruby-3.3.12:/home/.rvm/gems/ruby-3.3.12@global")
    }

    @Test func oneBrokenVersionDoesNotHideTheOthers() async {
        let fake = FakeRunner { command in
            if command.executable.path.contains("3.1.2") { return failed(exitCode: 1, standardError: "incompatible library version") }
            let isList = command.arguments.first == "list"
            return succeeded((try? Fixture.text(isList ? "gem-list-3.3.12.txt" : "gem-outdated-3.3.12.txt")) ?? "")
        }

        let result = await RubyScanner(installations: [rvm, older], runner: fake).scan()

        #expect(result.packages.count == 128)
        #expect(result.issues.map(\.group) == ["3.1.2"])
    }

    @Test func buildsCommandsForThePackagesVersionOnly() {
        let scanner = RubyScanner(installations: [rvm, older], runner: gem())
        let package = InstalledPackage(bucket: .ruby, kind: .gem, name: "rails", group: "3.1.2", installedVersion: "7.1.3")

        #expect(scanner.updateCommand(for: package)?.arguments == ["update", "rails", "--no-document"])
        #expect(scanner.updateCommand(for: package)?.executable.path == "/home/.rvm/rubies/ruby-3.1.2/bin/gem")
        #expect(scanner.uninstallCommand(for: package)?.arguments == ["uninstall", "rails", "--all", "--executables"])
        #expect(scanner.updateCommand(for: InstalledPackage(bucket: .node, kind: .npmGlobal, name: "x", group: "3.1.2", installedVersion: "1")) == nil)
    }
}
