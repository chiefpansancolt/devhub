import Foundation
import Testing
@testable import DevHubCore

private func installedPackage(_ name: String, bucket: Bucket, kind: PackageKind, group: String?) -> InstalledPackage {
    InstalledPackage(bucket: bucket, kind: kind, name: name, group: group, installedVersion: "1.0.0")
}

@Suite struct StandardStatusTests {
    private func lists(_ build: (inout StandardPackageLists) -> Void) -> StandardPackageLists {
        var lists = StandardPackageLists()
        build(&lists)
        return lists
    }

    @Test func nodeHasATargetPerVersionAndPerManager() {
        let standard = lists { $0.add(["typescript", "eslint"], kind: .npmGlobal, to: .node) }
        let packages = [
            installedPackage("typescript", bucket: .node, kind: .npmGlobal, group: "24.21.0"),
            installedPackage("eslint", bucket: .node, kind: .pnpmGlobal, group: "pnpm")
        ]

        let status = StandardStatus.status(for: .node, lists: standard, groups: ["26.1.0", "24.21.0", "pnpm", "Bun"], packages: packages)

        #expect(status.map(\.target.group) == ["26.1.0", "24.21.0", "pnpm", "Bun"])
        #expect(status.map(\.installed) == [0, 1, 1, 0])
        #expect(status[1].missing.map(\.name) == ["eslint"])
        #expect(status[2].missing.map(\.name) == ["typescript"])
        #expect(status.map(\.target.isVersion) == [true, true, false, false])
    }

    @Test func aPackageOfAnotherManagerDoesNotCount() {
        let standard = lists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }
        let packages = [installedPackage("eslint", bucket: .node, kind: .npmGlobal, group: "pnpm")]

        let status = StandardStatus.status(for: .node, lists: standard, groups: ["pnpm"], packages: packages)

        #expect(status[0].missing.map(\.name) == ["eslint"])
    }

    @Test func homebrewHasOneTargetAndTellsFormulaeFromCasks() {
        let standard = lists {
            $0.add(["docker"], kind: .formula, to: .homebrew)
            $0.add(["docker"], kind: .cask, to: .homebrew)
        }
        let packages = [installedPackage("docker", bucket: .homebrew, kind: .formula, group: nil)]

        let status = StandardStatus.status(for: .homebrew, lists: standard, groups: ["ignored"], packages: packages)

        #expect(status.count == 1)
        #expect(status[0].target.group == nil)
        #expect(status[0].missing.map(\.kind) == [.cask])
    }

    @Test func aToolchainMatchesItsInstalledNameWithTheTarget() {
        let standard = lists {
            $0.add(["stable", "nightly"], kind: .rustToolchain, to: .rust)
            $0.add(["hexyl"], kind: .cargoTool, to: .rust)
        }
        let packages = [
            installedPackage("stable-aarch64-apple-darwin", bucket: .rust, kind: .rustToolchain, group: nil),
            installedPackage("hexyl", bucket: .rust, kind: .cargoTool, group: nil)
        ]

        let status = StandardStatus.status(for: .rust, lists: standard, groups: [], packages: packages)

        #expect(status[0].missing.map(\.name) == ["nightly"])
    }

    @Test func aChannelNameDoesNotMatchANameThatMerelyStartsWithIt() {
        let standard = lists { $0.add(["stable"], kind: .rustToolchain, to: .rust) }
        let packages = [installedPackage("stableish", bucket: .rust, kind: .rustToolchain, group: nil)]

        #expect(StandardStatus.status(for: .rust, lists: standard, groups: [], packages: packages)[0].missing.count == 1)
    }

    @Test func pythonHasATargetPerManager() {
        let standard = lists { $0.add(["black"], kind: .pythonTool, to: .python) }
        let packages = [installedPackage("black", bucket: .python, kind: .pythonTool, group: "uv")]

        let status = StandardStatus.status(for: .python, lists: standard, groups: ["pipx", "uv"], packages: packages)

        #expect(status.map(\.isComplete) == [false, true])
    }

    @Test func anEmptyListIsNeverComplete() {
        let status = StandardStatus.status(for: .ruby, lists: StandardPackageLists(), groups: ["3.4.1"], packages: [])

        #expect(status[0].total == 0)
        #expect(!status[0].isComplete)
    }

    @Test func theSubjectOfAManagerTargetUsesTheManagersKind() {
        let entry = StandardEntry(name: "cowsay", kind: .npmGlobal)

        #expect(StandardStatus.subject(for: entry, in: StandardTarget(bucket: .node, group: "pnpm")).kind == .pnpmGlobal)
        #expect(StandardStatus.subject(for: entry, in: StandardTarget(bucket: .node, group: "Bun")).kind == .bunGlobal)
        #expect(StandardStatus.subject(for: entry, in: StandardTarget(bucket: .node, group: "Yarn")).kind == .yarnGlobal)
        #expect(StandardStatus.subject(for: entry, in: StandardTarget(bucket: .node, group: "26.1.0")).kind == .npmGlobal)
        #expect(StandardStatus.subject(for: entry, in: StandardTarget(bucket: .node, group: "26.1.0")).group == "26.1.0")
    }
}

private final class ToolchainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Toolchain

    init(_ toolchain: Toolchain) { current = toolchain }

    var toolchain: Toolchain {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

private func nodeToolchain(_ versions: [String]) -> Toolchain {
    Toolchain(homebrew: nil, node: versions.map { NodeInstallation(version: $0, manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v\($0)")) }, ruby: [])
}

private func nodeVersion(of command: ToolCommand) -> String {
    let parts = command.executable.path.split(separator: "/").map(String.init)
    return parts.first { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }.map { String($0.dropFirst()) } ?? ""
}

@MainActor
@Suite struct StandardPackagesStateTests {
    private final class World: @unchecked Sendable {
        let box: ToolchainBox
        var installed: [String: [String]]
        /// The newest version of each package and the engines of that version. A package that is missing here is not found.
        var latest: [String: (version: String, engines: String?)]
        /// The versions of a package, and the engines of each version, for the search that runs when the newest does not suit.
        var versions: [String: [String]]
        var engines: [String: String]
        var offline = false

        init(versions: [String], installed: [String: [String]], latest: [String: (version: String, engines: String?)] = [:], older: [String: [String]] = [:], engines: [String: String] = [:]) {
            box = ToolchainBox(nodeToolchain(versions))
            self.installed = installed
            self.latest = latest
            self.versions = older
            self.engines = engines
        }

        private static func entry(_ version: String, _ engines: String?) -> String {
            engines.map { #"[{"version":"\#(version)","engines.node":"\#($0)"}]"# } ?? #"["\#(version)"]"#
        }

        func runner() -> FakeRunner {
            FakeRunner { [self] command in
                let arguments = command.arguments
                switch arguments.first {
                case "ls":
                    let names = installed[nodeVersion(of: command)] ?? []
                    let entries = names.map { #""\#($0)":{"version":"1.0.0"}"# }.joined(separator: ",")
                    return succeeded(#"{"dependencies":{\#(entries)}}"#)
                case "outdated":
                    return succeeded("{}")
                case "view":
                    if offline { return failed(exitCode: 1, standardError: "npm error code ENOTFOUND") }
                    let target = arguments[1]
                    if arguments[2] == "versions" {
                        let list = (versions[target] ?? []).map { "\"\($0)\"" }.joined(separator: ",")
                        return succeeded("[\(list)]")
                    }
                    if let at = target.lastIndex(of: "@"), at != target.startIndex {
                        return succeeded(Self.entry(String(target[target.index(after: at)...]), engines[target]))
                    }
                    guard let newest = latest[target] else { return failed(exitCode: 1, standardError: "npm error code E404") }
                    return succeeded(Self.entry(newest.version, newest.engines))
                default:
                    return succeeded("installed")
                }
            }
        }
    }

    private func settings(_ names: [String], banner: Bool = true, notify: Bool = false) -> SettingsValues {
        var values = SettingsValues()
        values.standardPackages.add(names, kind: .npmGlobal, to: .node)
        if !banner { values.disabledStandardBanners = ["node", "ruby"] }
        values.notifyStandardPackages = notify
        return values
    }

    private func makeState(_ world: World, ledger: VersionLedger? = nil, notifier: (any NotificationSending)? = nil, standard: [String] = ["typescript", "eslint"]) -> (AppState, FakeRunner, VersionLedger) {
        let name = "devhub-tests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let versionLedger = ledger ?? VersionLedger(defaults: suite)
        let runner = world.runner()
        let box = world.box
        let state = AppState(scanners: [:], runner: runner, history: HistoryStore(), notifier: notifier, versionLedger: versionLedger, toolchainDetector: { _ in box.toolchain })
        state.apply(settings(standard))
        return (state, runner, versionLedger)
    }

    @Test func anOfferShowsOnItsToolAndOnItsVersionOnly() async {
        let world = World(versions: ["24.21.0"], installed: ["24.21.0": []])
        let (state, _, _) = makeState(world)
        await state.refresh()
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])
        world.installed["26.1.0"] = ["eslint"]
        await state.refresh()
        #expect(state.standardOffers.map(\.id) == ["node/26.1.0"])

        #expect(state.standardOffers(in: PackageScope(bucket: .node)).map(\.id) == ["node/26.1.0"])
        #expect(state.standardOffers(in: PackageScope(bucket: .node, group: "26.1.0")).map(\.id) == ["node/26.1.0"])
        #expect(state.standardOffers(in: PackageScope(bucket: .node, group: "24.21.0")).isEmpty)
        #expect(state.standardOffers(in: PackageScope(bucket: .ruby)).isEmpty)
        #expect(state.standardOffers(in: PackageScope(bucket: .homebrew)).isEmpty)
    }

    @Test func aVersionThatAppearsLaterIsOfferedTheMissingPackages() async {
        let world = World(versions: ["24.21.0"], installed: ["24.21.0": []])
        let (state, _, _) = makeState(world)
        await state.refresh()
        #expect(state.standardOffers.isEmpty)

        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])
        world.installed["26.1.0"] = ["eslint"]
        await state.refresh()

        #expect(state.standardOffers.map(\.id) == ["node/26.1.0"])
        #expect(state.standardOffers.first?.missing.map(\.name) == ["typescript"])
    }

    @Test func theVersionsThatExistedAtTheFirstRunAreNeverOffered() async {
        let world = World(versions: ["24.21.0", "22.11.0"], installed: [:])
        let (state, _, ledger) = makeState(world)

        await state.refresh()

        #expect(state.standardOffers.isEmpty)
        #expect(ledger.snapshot.isSeeded)
        #expect(ledger.snapshot.baseline == ["node/24.21.0", "node/22.11.0"])
    }

    @Test func dismissingAnOfferHidesItUntilTheListChanges() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let (state, _, _) = makeState(world)
        await state.refresh()
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])
        await state.refresh()
        let offer = try! #require(state.standardOffers.first)

        #expect(!state.isStandardOfferDismissed(bucket: .node, version: "26.1.0"))
        state.dismissStandardOffer(offer)
        #expect(state.standardOffers.isEmpty)
        #expect(state.isStandardOfferDismissed(bucket: .node, version: "26.1.0"))

        await state.refresh()
        #expect(state.standardOffers.isEmpty)

        state.apply(settings(["typescript", "eslint", "prettier"]))
        #expect(state.standardOffers.map(\.id) == ["node/26.1.0"])
    }

    @Test func aCompleteVersionHasNoOffer() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let (state, _, _) = makeState(world)
        await state.refresh()
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])
        world.installed["26.1.0"] = ["typescript", "eslint"]

        await state.refresh()

        #expect(state.standardOffers.isEmpty)
    }

    @Test func turningTheBannerOffRemovesTheOffers() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let (state, _, _) = makeState(world)
        await state.refresh()
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])
        await state.refresh()
        #expect(!state.standardOffers.isEmpty)

        state.apply(settings(["typescript", "eslint"], banner: false))

        #expect(state.standardOffers.isEmpty)
    }

    @Test func aScheduledCheckAnnouncesAnOfferOnlyOnce() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let notifier = FakeNotifier()
        let (state, _, _) = makeState(world, notifier: notifier)
        state.apply(settings(["typescript"], notify: true))
        await state.refresh(.check, trigger: .automatic)
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])

        await state.refresh(.check, trigger: .automatic)
        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications.first?.body == "Node 26.1.0")
    }

    @Test func noNotificationWhenTheSettingIsOff() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let notifier = FakeNotifier()
        let (state, _, _) = makeState(world, notifier: notifier)
        await state.refresh(.check, trigger: .automatic)
        world.box.toolchain = nodeToolchain(["26.1.0", "24.21.0"])

        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications.isEmpty)
        #expect(state.standardOffers.count == 1)
    }

    @Test func installingStandardPackagesPicksTheNewestVersionTheNodeVersionCanRun() async throws {
        let world = World(
            versions: ["18.20.4"], installed: ["18.20.4": []],
            latest: ["typescript": ("5.6.3", ">=14.17"), "eslint": ("10.12.0", "^20.19.0 || >=24")],
            older: ["eslint": ["9.39.0", "10.12.0"]],
            engines: ["eslint@9.39.0": "^18.18.0 || >=20.9.0"]
        )
        let (state, runner, _) = makeState(world)
        await state.refresh()

        await state.installStandard(bucket: .node, group: "18.20.4")

        let installs = runner.commands.filter { $0.arguments.first == "install" }.map(\.arguments)
        #expect(installs == [["install", "-g", "eslint@9.39.0"], ["install", "-g", "typescript@5.6.3"]])
        let history = state.history.entries.filter { $0.action == .install }
        #expect(history.count == 2)
        #expect(Set(history.compactMap(\.toVersion)) == ["9.39.0", "5.6.3"])
        #expect(history.allSatisfy { $0.group == "18.20.4" })
    }

    @Test func aPackageThatIsNotFoundOrCannotRunIsSkippedAndLogged() async {
        let world = World(
            versions: ["18.20.4"], installed: ["18.20.4": []],
            latest: ["eslint": ("10.0.0", ">=22")],
            older: ["eslint": ["10.0.0"]]
        )
        let (state, runner, _) = makeState(world, standard: ["eslint", "typescrpt"])
        await state.refresh()

        await state.installStandard(bucket: .node, group: "18.20.4")

        #expect(!runner.commands.contains { $0.arguments.first == "install" })
        let messages = state.log.map(\.entry.text)
        #expect(messages.contains("Skipped eslint: no version of it supports Node 18.20.4."))
        #expect(messages.contains("Skipped typescrpt: no package with that name was found."))
        #expect(state.session == nil)
        #expect(!state.isBusy)
    }

    @Test func whenTheRegistryCannotBeReachedTheNewestVersionInstalls() async {
        let world = World(versions: ["24.21.0"], installed: ["24.21.0": []])
        world.offline = true
        let (state, runner, _) = makeState(world, standard: ["typescript"])
        await state.refresh()

        await state.installStandard(bucket: .node, group: "24.21.0")

        #expect(runner.commands.filter { $0.arguments.first == "install" }.map(\.arguments) == [["install", "-g", "typescript@latest"]])
    }

    @Test func aVersionWithNothingMissingStartsNoInstall() async {
        let world = World(versions: ["24.21.0"], installed: ["24.21.0": ["typescript", "eslint"]])
        let (state, runner, _) = makeState(world)
        await state.refresh()

        await state.installStandard(bucket: .node, group: "24.21.0")

        #expect(!runner.commands.contains { $0.arguments.first == "install" })
        #expect(state.session == nil)
    }

    @Test func aTargetThatIsNotKnownStartsNoInstall() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let (state, runner, _) = makeState(world)
        await state.refresh()

        await state.installStandard(bucket: .node, group: "99.0.0")

        #expect(!runner.commands.contains { $0.arguments.first == "install" })
    }

    @Test func validatingReportsEveryEntryWithoutInstalling() async {
        let world = World(
            versions: ["24.21.0"], installed: ["24.21.0": []],
            latest: ["eslint": ("10.12.0", ">=20")]
        )
        let (state, runner, _) = makeState(world, standard: ["eslint", "typescrpt"])
        await state.refresh()

        let result = await state.validateStandard(bucket: .node, group: "24.21.0")

        #expect(result["npmGlobal/eslint"] == .current(version: "10.12.0"))
        #expect(result["npmGlobal/typescrpt"] == .notFound)
        #expect(!runner.commands.contains { $0.arguments.first == "install" })
    }

    @Test func validatingATargetWithoutAScannerIsUnavailable() async {
        let world = World(versions: [], installed: [:])
        let (state, _, _) = makeState(world)

        let result = await state.validateStandard(bucket: .node, group: "24.21.0")

        #expect(result.values.allSatisfy { $0.isUnavailable })
        #expect(result.count == 2)
    }

    @Test func aTargetThatIsNotSetUpSaysSo() async {
        let world = World(versions: [], installed: [:])
        let (state, _, _) = makeState(world)

        let result = await state.validateStandard(bucket: .node, group: "24.21.0")

        guard case let .unavailable(reason, _)? = result["npmGlobal/typescript"] else { Issue.record("Expected unavailable"); return }
        #expect(reason == "Node is not set up on this Mac.")
    }

    @Test func aTargetThatTheToolCannotCheckSaysSo() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        let (state, _, _) = makeState(world)
        await state.refresh()

        let result = await state.validateStandard(bucket: .node, group: "99.0.0")

        guard case let .unavailable(reason, _)? = result["npmGlobal/typescript"] else { Issue.record("Expected unavailable"); return }
        #expect(reason == "DevHub cannot check this package here.")
    }

    @Test func whyAPackageCouldNotBeCheckedIsWrittenToTheOutputLog() async {
        let world = World(versions: ["24.21.0"], installed: [:])
        world.offline = true
        let (state, _, _) = makeState(world, standard: ["eslint"])
        await state.refresh()

        _ = await state.validateStandard(bucket: .node, group: "24.21.0")

        let messages = state.log.map(\.entry.text)
        #expect(messages.contains("eslint: npm failed: npm error code ENOTFOUND"))
        #expect(messages.contains("    npm error code ENOTFOUND"))
    }

    @Test func aPackageThatCouldBeCheckedLeavesNothingInTheLog() async {
        let world = World(versions: ["24.21.0"], installed: [:], latest: ["eslint": ("10.12.0", ">=20")])
        let (state, _, _) = makeState(world, standard: ["eslint"])
        await state.refresh()

        _ = await state.validateStandard(bucket: .node, group: "24.21.0")

        #expect(state.log.isEmpty)
    }

    @Test func theStatusFollowsTheScanResults() async {
        let world = World(versions: ["24.21.0"], installed: ["24.21.0": ["eslint"]])
        let (state, _, _) = makeState(world)
        await state.refresh()

        let status = state.standardStatus(for: .node)

        #expect(status.map(\.target.group) == ["24.21.0"])
        #expect(status[0].missing.map(\.name) == ["typescript"])
        #expect(status[0].installed == 1)
    }
}

@Suite struct StandardFillTests {
    private func package(_ name: String, bucket: Bucket, kind: PackageKind, group: String?, onRequest: Bool = true) -> InstalledPackage {
        InstalledPackage(bucket: bucket, kind: kind, name: name, group: group, installedVersion: "1.0.0", installedOnRequest: onRequest)
    }

    @Test func fillingFromANodeVersionLeavesOutWhatNodeInstallsItself() {
        let packages = [
            package("typescript", bucket: .node, kind: .npmGlobal, group: "24.21.0"),
            package("npm", bucket: .node, kind: .npmGlobal, group: "24.21.0"),
            package("corepack", bucket: .node, kind: .npmGlobal, group: "24.21.0"),
            package("vercel", bucket: .node, kind: .npmGlobal, group: "22.11.0")
        ]

        let entries = StandardStatus.entries(installedIn: StandardTarget(bucket: .node, group: "24.21.0"), packages: packages)

        #expect(entries.map(\.name) == ["typescript"])
    }

    @Test func fillingFromAManagerGivesPlainNpmEntries() {
        let packages = [package("cowsay", bucket: .node, kind: .pnpmGlobal, group: "pnpm")]

        let entries = StandardStatus.entries(installedIn: StandardTarget(bucket: .node, group: "pnpm"), packages: packages)

        #expect(entries == [StandardEntry(name: "cowsay", kind: .npmGlobal)])
    }

    @Test func fillingFromRubyLeavesOutBundler() {
        let packages = [package("bundler", bucket: .ruby, kind: .gem, group: "3.4.1"), package("rails", bucket: .ruby, kind: .gem, group: "3.4.1")]

        #expect(StandardStatus.entries(installedIn: StandardTarget(bucket: .ruby, group: "3.4.1"), packages: packages).map(\.name) == ["rails"])
    }

    @Test func fillingFromHomebrewKeepsWhatTheUserInstalledAndAllCasks() {
        let packages = [
            package("git", bucket: .homebrew, kind: .formula, group: nil),
            package("openssl@3", bucket: .homebrew, kind: .formula, group: nil, onRequest: false),
            package("raycast", bucket: .homebrew, kind: .cask, group: nil)
        ]

        let entries = StandardStatus.entries(installedIn: StandardTarget(bucket: .homebrew, group: nil), packages: packages)

        #expect(entries.map(\.id) == ["formula/git", "cask/raycast"])
    }

    @Test func fillingFromRustLeavesOutRustupItself() {
        let packages = [
            package("rustup", bucket: .rust, kind: .rustToolchain, group: nil),
            package("stable-aarch64-apple-darwin", bucket: .rust, kind: .rustToolchain, group: nil),
            package("hexyl", bucket: .rust, kind: .cargoTool, group: nil)
        ]

        let entries = StandardStatus.entries(installedIn: StandardTarget(bucket: .rust, group: nil), packages: packages)

        #expect(entries.map(\.name) == ["stable-aarch64-apple-darwin", "hexyl"])
    }

    @Test func aNameThatCouldBeAnOptionIsNeverTakenIntoTheList() {
        let packages = [package("--evil", bucket: .python, kind: .pythonTool, group: "uv"), package("black", bucket: .python, kind: .pythonTool, group: "uv")]

        #expect(StandardStatus.entries(installedIn: StandardTarget(bucket: .python, group: "uv"), packages: packages).map(\.name) == ["black"])
    }
}
