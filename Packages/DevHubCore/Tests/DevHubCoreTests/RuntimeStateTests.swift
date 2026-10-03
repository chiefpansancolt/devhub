import Foundation
import Testing
@testable import DevHubCore

private final class StubReleases: RuntimeReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var lists: [Bucket: [String]]
    private var fetched: [Bucket] = []
    var failure: (any Error)?

    init(_ lists: [Bucket: [String]]) { self.lists = lists }

    func fetchCount(for bucket: Bucket) -> Int { lock.withLock { fetched.filter { $0 == bucket }.count } }

    func releases(for bucket: Bucket) async throws -> [String] {
        try lock.withLock {
            fetched.append(bucket)
            if let failure { throw failure }
            return lists[bucket] ?? []
        }
    }
}

private final class Machine: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: [String]
    private var current: Date

    init(_ installed: [String], now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.installed = installed
        current = now
    }

    var toolchain: Toolchain {
        lock.withLock {
            Toolchain(homebrew: nil, node: installed.map { NodeInstallation(version: $0, manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v\($0)")) }, ruby: [])
        }
    }

    func install(_ version: String) { lock.withLock { installed.append(version) } }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@MainActor
@Suite struct RuntimeStateTests {
    private let releases = ["26.10.0", "26.9.0", "24.21.0", "24.20.0"]

    private func makeState(
        installed: [String] = ["24.20.0"],
        source: StubReleases? = nil,
        settings: SettingsValues = SettingsValues(),
        runner: FakeRunner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
    ) -> (AppState, Machine, StubReleases, VersionLedger) {
        let name = "devhub-tests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let ledger = VersionLedger(defaults: suite)
        let machine = Machine(installed)
        let stub = source ?? StubReleases([.node: releases])
        let scanner = NodeScanner(installations: machine.toolchain.node, runner: runner)
        let state = AppState(
            scanners: [.node: scanner], runner: runner, history: HistoryStore(), versionLedger: ledger,
            runtimeReleaseSource: stub, toolchainDetector: { _ in machine.toolchain }, now: { machine.now }
        )
        state.apply(settings)
        return (state, machine, stub, ledger)
    }

    @Test func aNewerVersionIsOfferedAfterTheReleasesAreFetched() async {
        let (state, _, _, _) = makeState()
        #expect(state.runtimeOffers.isEmpty)

        await state.checkRuntimeReleases(force: false)

        #expect(state.runtimeOffers.map(\.version) == ["26.10.0", "24.21.0"])
    }

    @Test func aMachineWithoutAnInstallerHasNoSource() async {
        let (state, _, _, _) = makeState()
        let withoutSource = AppState(scanners: [:], runner: FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }, runtimeVersions: [RuntimeVersion(bucket: .node, version: "24.20.0", manager: .nvm)])

        await withoutSource.checkRuntimeReleases(force: true)

        #expect(withoutSource.runtimeOffers.isEmpty)
        #expect(state.runtimeOffers.isEmpty)
    }

    @Test func aListThatWasFetchedInTheLastDayIsNotFetchedAgain() async {
        let (state, machine, source, _) = makeState()
        await state.checkRuntimeReleases(force: false)
        let first = source.fetchCount(for: .node)

        machine.advance(23 * 60 * 60)
        await state.checkRuntimeReleases(force: false)
        #expect(source.fetchCount(for: .node) == first)

        machine.advance(2 * 60 * 60)
        await state.checkRuntimeReleases(force: false)
        #expect(source.fetchCount(for: .node) == first + 1)
    }

    @Test func aManualCheckFetchesAgain() async {
        let (state, _, source, _) = makeState()
        await state.checkRuntimeReleases(force: false)
        let first = source.fetchCount(for: .node)

        await state.checkRuntimeReleases(force: true)

        #expect(source.fetchCount(for: .node) == first + 1)
    }

    @Test func aNormalCheckLooksForNewVersions() async {
        let (state, _, _, _) = makeState()

        await state.refresh(.check, trigger: .manual)
        await waitUntil { !state.runtimeOffers.isEmpty }

        #expect(state.runtimeOffers.map(\.version) == ["26.10.0", "24.21.0"])
    }

    @Test func theScanAfterAnActionDoesNotFetchTheLists() async {
        let (state, _, source, _) = makeState()

        await state.refresh(.afterUpdate)

        #expect(source.fetchCount(for: .node) == 0)
    }

    @Test func switchingOffOneToolStillChecksTheOther() async {
        var values = SettingsValues()
        values.disabledRuntimeChecks = ["node"]
        let (state, _, source, _) = makeState(settings: values)

        await state.checkRuntimeReleases(force: true)

        #expect(source.fetchCount(for: .ruby) == 1)
    }

    @Test func switchingTheCheckOnAgainFetchesAtOnce() async {
        var off = SettingsValues()
        off.disabledRuntimeChecks = ["node"]
        let (state, _, _, _) = makeState(settings: off)

        state.apply(SettingsValues())
        await waitUntil { !state.runtimeOffers.isEmpty }

        #expect(state.runtimeOffers.map(\.version) == ["26.10.0", "24.21.0"])
    }

    @Test func switchingTheCheckOffForATooHidesItsOffersAndStopsFetching() async {
        var values = SettingsValues()
        values.disabledRuntimeChecks = ["node"]
        let (state, _, source, _) = makeState(settings: values)

        await state.checkRuntimeReleases(force: true)

        #expect(state.runtimeOffers.isEmpty)
        #expect(source.fetchCount(for: .node) == 0)
    }

    @Test func switchingTheCheckOffRemovesTheBannerThatIsShowing() async {
        let (state, _, _, _) = makeState()
        await state.checkRuntimeReleases(force: false)
        #expect(!state.runtimeOffers.isEmpty)

        var values = SettingsValues()
        values.disabledRuntimeChecks = ["node"]
        state.apply(values)

        #expect(state.runtimeOffers.isEmpty)
    }

    @Test func aFailedFetchLeavesNoOfferAndWritesTheReasonToTheLog() async {
        let stub = StubReleases([:])
        stub.failure = RuntimeReleaseError.badStatus(503)
        let (state, _, _, _) = makeState(source: stub)

        await state.checkRuntimeReleases(force: true)

        #expect(state.runtimeOffers.isEmpty)
        #expect(state.log.map(\.entry.text).contains("Could not check for new Node versions: The release list answered with status 503."))
    }

    @Test func aFailedFetchKeepsTheOffersThatWereAlreadyKnown() async {
        let stub = StubReleases([.node: releases])
        let (state, _, _, _) = makeState(source: stub)
        await state.checkRuntimeReleases(force: false)
        stub.failure = RuntimeReleaseError.unreadable

        await state.checkRuntimeReleases(force: true)

        #expect(state.runtimeOffers.map(\.version) == ["26.10.0", "24.21.0"])
    }

    @Test func dismissingAnOfferHidesItAndKeepsTheOthers() async {
        let (state, _, _, ledger) = makeState()
        await state.checkRuntimeReleases(force: false)

        state.dismissRuntimeOffer(state.runtimeOffers[0])

        #expect(state.runtimeOffers.map(\.version) == ["24.21.0"])
        #expect(ledger.snapshot.dismissed.contains("runtime/node/26.10.0"))
    }

    @Test func aDismissalSurvivesTheNextFetch() async {
        let (state, _, _, _) = makeState()
        await state.checkRuntimeReleases(force: false)
        state.dismissRuntimeOffer(state.runtimeOffers[0])

        await state.checkRuntimeReleases(force: true)

        #expect(state.runtimeOffers.map(\.version) == ["24.21.0"])
    }

    @Test func installingRunsTheManagerCommandThroughTheInstallEngine() async throws {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)

        await state.installRuntime(state.runtimeOffers[0], asDefault: true)

        let command = try #require(runner.commands.first)
        #expect(command.executable.path == "/bin/bash")
        #expect(command.arguments.last == ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0 && nvm alias default 26.10.0")
    }

    @Test func aVersionInstallsWithoutTheDefaultChangeWhenAskedTo() async throws {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)
        let patch = try #require(state.runtimeOffers.first { $0.version == "24.21.0" })

        await state.installRuntime(patch, asDefault: false)

        #expect(runner.commands.first?.arguments.last == ". \"$NVM_DIR/nvm.sh\" && nvm install 24.21.0")
    }

    @Test func theSameOfferCanInstallWithOrWithoutTheDefaultChange() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)
        let offer = state.runtimeOffers[0]

        await state.installRuntime(offer, asDefault: false)
        state.dismissSession()
        await state.installRuntime(offer, asDefault: true)

        #expect(runner.commands.filter { $0.executable.path == "/bin/bash" }.map { $0.arguments.last } == [
            ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0",
            ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0 && nvm alias default 26.10.0"
        ])
    }

    @Test func theButtonsStartTheInstallWithTheirChoice() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)
        let offer = state.runtimeOffers[0]

        state.startInstallRuntime(offer, asDefault: false)
        await waitUntil { runner.commands.contains { $0.executable.path == "/bin/bash" } && !state.isBusy }
        #expect(runner.commands.first { $0.executable.path == "/bin/bash" }?.arguments.last == ". \"$NVM_DIR/nvm.sh\" && nvm install 26.10.0")

        state.startInstallRuntime(offer, asDefault: true)
        await waitUntil { runner.commands.filter { $0.executable.path == "/bin/bash" }.count == 2 && !state.isBusy }
        #expect(runner.commands.last { $0.executable.path == "/bin/bash" }?.arguments.last?.hasSuffix("nvm alias default 26.10.0") == true)
    }

    @Test func theNewVersionIsFoundAfterTheInstallAndTheBannerGoesAway() async {
        let (state, machine, _, _) = makeState()
        await state.checkRuntimeReleases(force: false)
        let offer = state.runtimeOffers[0]
        machine.install("26.10.0")

        await state.installRuntime(offer, asDefault: true)

        #expect(!state.runtimeOffers.contains { $0.version == "26.10.0" })
        #expect(state.groupScopes(of: .node).contains { $0.group == "26.10.0" })
    }

    @Test func aFailedInstallKeepsTheBanner() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, standardOutput: "", standardError: "nvm: command not found") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)

        await state.installRuntime(state.runtimeOffers[0], asDefault: true)

        #expect(state.runtimeOffers.map(\.version) == ["26.10.0", "24.21.0"])
        #expect(state.session?.failedItems.count == 1)
    }

    @Test func theInstallIsWrittenToTheHistory() async throws {
        let (state, _, _, _) = makeState()
        await state.checkRuntimeReleases(force: false)

        await state.installRuntime(state.runtimeOffers[0], asDefault: true)

        await waitUntil { state.history.entries.contains { $0.action == .install } }
        let entry = try #require(state.history.entries.first { $0.action == .install })
        #expect(entry.package == "node")
        #expect(entry.group == "nvm")
        #expect(entry.toVersion == "26.10.0")
        #expect(entry.fromVersion == nil)
    }

    @Test func nothingInstallsWhileAnotherActionRuns() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        let (state, _, _, _) = makeState(runner: runner)
        await state.checkRuntimeReleases(force: false)
        let offer = state.runtimeOffers[0]
        state.isPreparingInstall = true

        await state.installRuntime(offer, asDefault: true)

        #expect(runner.commands.isEmpty)
    }
}
