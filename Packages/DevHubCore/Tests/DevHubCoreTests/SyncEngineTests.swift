import Foundation
import Testing
@testable import DevHubCore

private let pushDelay = Duration.seconds(3)
private let pollDelay = Duration.seconds(5)

private func node(_ names: String...) -> StandardPackageLists {
    makeLists { $0.add(names, kind: .npmGlobal, to: .node) }
}

private final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    let api: FakeGitHub
    let device: @Sendable (URLRequest) -> HTTPResponse

    init(api: FakeGitHub, device: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        self.api = api
        self.device = device
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        request.url?.host == "github.com" ? device(request) : try await api.send(request)
    }
}

private final class WaitCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (started: 0, cancelled: 0)
    var started: Int { lock.withLock { counts.started } }
    var cancelled: Int { lock.withLock { counts.cancelled } }
    func start() { lock.withLock { counts.started += 1 } }
    func cancel() { lock.withLock { counts.cancelled += 1 } }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Task<Void, Never>?
    var task: Task<Void, Never>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    func cancel() { task?.cancel() }
}

@MainActor
private final class ValuesBox {
    var values = SettingsValues()
}

@MainActor
private final class Rig {
    let github: FakeGitHub
    let tokens: FakeTokenStore
    let ledger: SyncLedger
    let pushGate = Gate()
    let pollGate = Gate(open: true)
    let pushWaits = WaitCounts()
    let suite: UserDefaults
    let box = ValuesBox()
    var state: AppState!

    var values: SettingsValues {
        get { box.values }
        set { box.values = newValue }
    }

    init(
        github: FakeGitHub = FakeGitHub(),
        local: StandardPackageLists = StandardPackageLists(),
        connected: Bool = true,
        automatic: Bool = true,
        tokens: FakeTokenStore = FakeTokenStore(),
        suite: UserDefaults? = nil,
        transport: (any HTTPTransport)? = nil
    ) {
        self.github = github
        self.tokens = tokens
        let name = "devhub-tests-\(UUID().uuidString)"
        let defaults = suite ?? UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        self.suite = defaults
        ledger = SyncLedger(defaults: defaults)
        box.values.standardPackages = local
        box.values.syncStandardPackagesAutomatically = automatic
        if connected { ledger.connect(login: "octo") }
        state = AppState(
            scanners: [:], runner: FakeRunner { _ in CommandResult(exitCode: 0, standardOutput: "", standardError: "") }, history: HistoryStore(),
            toolchainDetector: { _ in Toolchain(homebrew: nil, node: [], ruby: []) }, checkInterval: nil
        )
        state.apply(values)
        attach(transport: transport ?? github)
    }

    func attach(transport: any HTTPTransport) {
        let gate = pushGate
        let polls = pollGate
        let waits = pushWaits
        let services = SyncServices(
            clientID: "client-1", transport: transport, tokenStore: tokens, ledger: ledger,
            sleep: { duration in
                if duration == pushDelay {
                    waits.start()
                    do { try await gate.wait() } catch {
                        waits.cancel()
                        throw error
                    }
                }
                if duration == pollDelay { try await polls.wait() }
            },
            pushDelay: pushDelay
        )
        let box = box
        state.configureSync(services, lists: { box.values.standardPackages }, apply: { [weak state] merged in
            box.values.standardPackages = merged
            state?.apply(box.values)
        })
    }

    var lists: StandardPackageLists { values.standardPackages }

    func edit(_ change: (inout StandardPackageLists) -> Void) {
        change(&values.standardPackages)
        state.apply(values)
    }

    func setAutomatic(_ on: Bool) {
        values.syncStandardPackagesAutomatically = on
        state.apply(values)
    }

    func sync() async {
        await state.syncAndWait()
    }
}

@MainActor
@Suite struct SyncEngineTests {
    // MARK: First syncs

    @Test func aSecondMacTakesTheRemoteListWithoutUploading() async {
        let github = FakeGitHub()
        github.setRemote(node("eslint", "vercel"))
        let rig = Rig(github: github)

        await rig.sync()

        #expect(nodeNames(rig.lists) == ["eslint", "vercel"])
        #expect(github.puts == 0)
        #expect(github.createdRepositories == 0)
        #expect(rig.state.syncResult == .success(at: rig.state.syncResult!.at, summary: SyncSummary(added: 2, removed: 0)))
        #expect(rig.ledger.snapshot.base == node("eslint", "vercel"))
    }

    @Test func aFirstSyncCreatesThePrivateRepositoryAndUploadsTheLists() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("eslint"))

        await rig.sync()

        #expect(github.createdRepositories == 1)
        #expect(github.puts == 1)
        #expect(github.remoteLists == node("eslint"))
        #expect(rig.state.syncResult?.failure == nil)
        #expect(rig.state.syncResult?.summary == SyncSummary(added: 0, removed: 0))
        #expect(rig.ledger.snapshot.base == node("eslint"))
    }

    @Test func aFirstSyncThatFindsBothSidesMakesAUnionOnBoth() async {
        let github = FakeGitHub()
        github.setRemote(node("prettier", "eslint"))
        let rig = Rig(github: github, local: node("vercel", "eslint"))

        await rig.sync()

        #expect(nodeNames(rig.lists) == ["eslint", "prettier", "vercel"])
        #expect(github.remoteLists == node("eslint", "prettier", "vercel"))
        #expect(rig.state.syncResult?.summary == SyncSummary(added: 1, removed: 0))
    }

    @Test func nothingIsUploadedWhenBothSidesAlreadyAgree() async {
        let github = FakeGitHub()
        github.setRemote(node("eslint"))
        let rig = Rig(github: github, local: node("eslint"))

        await rig.sync()

        #expect(github.puts == 0)
        #expect(rig.state.syncResult?.summary?.isEmpty == true)
    }

    @Test func aRepositoryThatCameFromACreatedFileWithNoListsIsNotUploadedEmpty() async {
        let github = FakeGitHub()
        let rig = Rig(github: github)

        await rig.sync()

        #expect(github.puts == 0)
        #expect(github.fileData == nil)
        #expect(rig.state.syncResult?.failure == nil)
    }

    // MARK: Two Macs

    @Test func twoMacsConvergeOnAddsAndRemovals() async {
        let github = FakeGitHub()
        let mac1 = Rig(github: github, local: node("a", "b"))
        let mac2 = Rig(github: github)

        await mac1.sync()
        await mac2.sync()
        #expect(nodeNames(mac2.lists) == ["a", "b"])

        mac2.edit { $0.remove(StandardEntry(name: "b", kind: .npmGlobal), from: .node); $0.add(["d"], kind: .npmGlobal, to: .node) }
        mac1.edit { $0.add(["c"], kind: .npmGlobal, to: .node) }
        await mac2.sync()
        await mac1.sync()
        await mac2.sync()

        #expect(nodeNames(mac1.lists) == ["a", "c", "d"])
        #expect(nodeNames(mac2.lists) == ["a", "c", "d"])
        #expect(github.remoteLists == node("a", "c", "d"))
    }

    @Test func aFormulaAndACaskWithTheSameNameBothSurvive() async {
        let github = FakeGitHub()
        let mac1 = Rig(github: github, local: makeLists { $0.add(["jq"], kind: .formula, to: .homebrew) })
        let mac2 = Rig(github: github, local: makeLists { $0.add(["jq"], kind: .cask, to: .homebrew) })

        await mac1.sync()
        await mac2.sync()
        await mac1.sync()

        #expect(mac1.lists.entries(for: .homebrew).map(\.id) == ["formula/jq", "cask/jq"])
        #expect(mac2.lists.entries(for: .homebrew).map(\.id) == ["formula/jq", "cask/jq"])
    }

    @Test func everyToolSyncs() async {
        let github = FakeGitHub()
        let all = makeLists {
            $0.add(["git"], kind: .formula, to: .homebrew)
            $0.add(["eslint"], kind: .npmGlobal, to: .node)
            $0.add(["rails"], kind: .gem, to: .ruby)
            $0.add(["stable"], kind: .rustToolchain, to: .rust)
            $0.add(["black"], kind: .pythonTool, to: .python)
        }
        let mac1 = Rig(github: github, local: all)
        let mac2 = Rig(github: github)

        await mac1.sync()
        await mac2.sync()

        #expect(mac2.lists == all)
    }

    // MARK: Conflicts

    @Test func aFileThatChangedDuringTheSyncIsReadAndMergedAgain() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        let rig = Rig(github: github, local: node("a", "mine"))
        let changes = Counter()
        github.configure {
            $0.beforePut = { if changes.next() == 0 { github.setRemote(node("a", "theirs")) } }
        }

        await rig.sync()

        #expect(github.remoteLists == node("a", "mine", "theirs"))
        #expect(nodeNames(rig.lists) == ["a", "mine", "theirs"])
        #expect(github.contentGets == 2)
        #expect(github.puts == 1)
        #expect(rig.state.syncResult?.failure == nil)
    }

    @Test func aFileThatKeepsChangingFailsAfterThreeTries() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        let rig = Rig(github: github, local: node("a", "mine"))
        let changes = Counter()
        github.configure {
            $0.beforePut = { github.setRemote(node("a", "theirs\(changes.next())")) }
        }

        await rig.sync()

        #expect(github.contentGets == 3)
        #expect(rig.state.syncResult?.failure?.kind == .other)
        #expect(rig.state.syncResult?.failure?.message == "The file kept changing on GitHub. DevHub tries again at the next sync.")
        #expect(rig.ledger.snapshot.base.isEmpty)
    }

    @Test func aRepositoryThatGitHubHasNotFinishedCreatingIsRetried() async {
        let github = FakeGitHub()
        github.configure { $0.putNotFoundAnswers = 2 }
        let rig = Rig(github: github, local: node("eslint"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure == nil)
        #expect(github.remoteLists == node("eslint"))
        #expect(github.puts == 1)
    }

    @Test func aRepositoryThatAlreadyExistedIsNotRetriedWhenTheFileCannotBeWritten() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        github.configure { $0.putNotFoundAnswers = 1 }
        let rig = Rig(github: github, local: node("a", "mine"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.message == "GitHub has not finished creating the repository. DevHub tries again at the next sync.")
        #expect(github.puts == 0)
    }

    // MARK: Echo and debounce

    @Test func applyingPulledListsDoesNotScheduleAnUpload() async {
        let github = FakeGitHub()
        github.setRemote(node("eslint"))
        let rig = Rig(github: github)

        await rig.sync()

        #expect(rig.state.pushTask == nil)
        #expect(github.puts == 0)
    }

    @Test func anEditUploadsAfterTheDebounce() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("eslint"))
        await rig.sync()
        let putsBefore = github.puts

        rig.edit { $0.add(["vercel"], kind: .npmGlobal, to: .node) }
        #expect(github.puts == putsBefore)
        #expect(rig.state.pushTask != nil)

        rig.pushGate.release()
        await waitUntil { github.puts == putsBefore + 1 }

        #expect(github.remoteLists == node("eslint", "vercel"))
        #expect(rig.ledger.snapshot.base == node("eslint", "vercel"))
    }

    @Test func severalQuickEditsMakeOneUpload() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()
        let putsBefore = github.puts

        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        rig.edit { $0.add(["c"], kind: .npmGlobal, to: .node) }
        rig.edit { $0.add(["d"], kind: .npmGlobal, to: .node) }
        let getsBefore = github.contentGets
        rig.pushGate.release()
        await waitUntil { github.puts > putsBefore }
        try? await Task.sleep(for: .milliseconds(80))

        #expect(github.puts == putsBefore + 1)
        #expect(github.contentGets == getsBefore + 1)
        #expect(github.remoteLists == node("a", "b", "c", "d"))
    }

    @Test func aNewerEditReplacesTheWaitOfTheEarlierOne() async {
        let rig = Rig(github: FakeGitHub(), local: node("a"))
        await rig.sync()

        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        rig.edit { $0.add(["c"], kind: .npmGlobal, to: .node) }
        rig.edit { $0.add(["d"], kind: .npmGlobal, to: .node) }
        await waitUntil { rig.pushWaits.cancelled == 2 }

        #expect(rig.pushWaits.started == 3)
        #expect(rig.pushWaits.cancelled == 2)
    }

    @Test func anEditThatLeavesTheListsAsTheyWereSchedulesNothing() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()

        rig.edit { $0.add(["a"], kind: .npmGlobal, to: .node) }

        #expect(rig.state.pushTask == nil)
    }

    @Test func anEditNotRelatedToTheListsSchedulesNothing() async {
        let rig = Rig(github: FakeGitHub(), local: node("a"))

        rig.values.checkOnLaunch.toggle()
        rig.state.apply(rig.values)

        #expect(rig.state.pushTask == nil)
    }

    @Test func anEditMadeWhileTheSyncWaitsForGitHubIsIncluded() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        let gate = Gate()
        github.configure { $0.gate = gate }
        let rig = Rig(github: github, local: node("a"))

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        rig.edit { $0.add(["late"], kind: .npmGlobal, to: .node) }
        gate.release()
        await rig.state.syncTask?.value

        #expect(github.remoteLists == node("a", "late"))
        #expect(rig.ledger.snapshot.base == node("a", "late"))
    }

    // MARK: Serialization

    @Test func requestsWhileASyncRunsMakeExactlyOneMoreRound() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        let gate = Gate()
        github.configure { $0.gate = gate }
        let rig = Rig(github: github)

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        rig.state.requestSync()
        rig.state.requestSync()
        rig.state.requestSync()
        #expect(rig.state.isSyncing)
        gate.release()
        await rig.state.syncTask?.value

        #expect(github.contentGets == 2)
        #expect(!rig.state.isSyncing)
    }

    @Test func anEditMadeWhileASyncWaitsIsNotUndoneByThatSync() async {
        let github = FakeGitHub()
        github.setRemote(node("a", "b"))
        let gate = Gate(open: true)
        github.configure { $0.gate = gate }
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()
        gate.close()

        rig.state.requestSync()
        await waitUntil { github.contentGets == 2 }
        rig.edit { $0 = StandardPackageLists() }
        gate.release()
        await rig.state.syncTask?.value

        #expect(github.remoteLists?.isEmpty == true)
        #expect(rig.lists.isEmpty)
    }

    @Test func emptyingTheListsAndPressingSyncNowAtOnceKeepsThemEmpty() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()

        rig.edit { $0 = StandardPackageLists() }
        await rig.sync()

        #expect(rig.lists.isEmpty)
        #expect(github.remoteLists?.isEmpty == true)
    }

    @Test func anEditThatFailedToSyncIsStillAnEditOnTheNextTry() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()
        github.configure { $0.offline = true }
        rig.edit { $0 = StandardPackageLists() }
        await rig.sync()

        github.configure { $0.offline = false }
        await rig.sync()

        #expect(rig.lists.isEmpty)
        #expect(github.remoteLists?.isEmpty == true)
    }

    @Test func aDisconnectDuringASyncChangesNothingAfterwards() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let gate = Gate()
        github.configure { $0.gate = gate }
        let rig = Rig(github: github)

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        await rig.state.disconnectGitHub()
        gate.release()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.lists.isEmpty)
        #expect(rig.state.syncAccountLogin == nil)
        #expect(rig.ledger.snapshot == SyncLedger.Snapshot())
        #expect(!rig.state.isSyncing)
        #expect(rig.tokens.current == nil)
        #expect(github.puts == 0)
    }

    @Test func aSuccessThatArrivesAfterADisconnectIsNotRecorded() async {
        let github = FakeGitHub()
        let putGate = Gate()
        github.configure { $0.putGate = putGate }
        let rig = Rig(github: github, local: node("a"))

        rig.state.requestSync()
        await waitUntil { github.putsStarted == 1 }
        await rig.state.disconnectGitHub()
        putGate.release()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.ledger.snapshot == SyncLedger.Snapshot())
        #expect(rig.state.syncResult == nil)
        #expect(rig.state.syncAccountLogin == nil)
    }

    @Test func aFailureThatArrivesAfterADisconnectIsNotRecordedOrLogged() async {
        let github = FakeGitHub()
        let putGate = Gate()
        github.configure { $0.putGate = putGate; $0.putStatus = 500 }
        let rig = Rig(github: github, local: node("a"))

        rig.state.requestSync()
        await waitUntil { github.putsStarted == 1 }
        await rig.state.disconnectGitHub()
        putGate.release()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.ledger.snapshot == SyncLedger.Snapshot())
        #expect(rig.state.log.isEmpty)
    }

    @Test func aSyncThatWasStoppedByADisconnectDoesNotResetTheNewSyncAfterReconnecting() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let oldGate = Gate()
        let newGate = Gate()
        github.configure { $0.getGates = [oldGate, newGate] }
        let rig = Rig(github: github)

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        await rig.state.disconnectGitHub()
        try? await rig.tokens.save("token-2")
        rig.ledger.connect(login: "octo")
        rig.state.publishSyncState()
        rig.state.requestSync()
        await waitUntil { github.contentGets == 2 }

        oldGate.release()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(rig.state.isSyncing)
        #expect(rig.state.syncTask != nil)

        newGate.release()
        await rig.state.syncTask?.value
        #expect(!rig.state.isSyncing)
        #expect(nodeNames(rig.lists) == ["remote"])
    }

    @Test func aDisconnectThatArrivesAsTheReadCompletesStopsTheSyncBeforeItChangesAnything() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let box = TaskBox()
        github.configure { $0.beforeContentGet = { box.cancel() } }
        let rig = Rig(github: github, local: node("mine"))

        rig.state.requestSync()
        box.task = rig.state.syncTask
        await rig.state.syncTask?.value

        #expect(nodeNames(rig.lists) == ["mine"])
        #expect(github.puts == 0)
        #expect(rig.state.syncResult == nil)
    }

    @Test func afterADisconnectDuringASyncANewConnectionCanSyncAgain() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let gate = Gate()
        github.configure { $0.gate = gate }
        let rig = Rig(github: github)

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        await rig.state.disconnectGitHub()
        gate.release()
        try? await Task.sleep(for: .milliseconds(60))
        try? await rig.tokens.save("token-2")
        rig.ledger.connect(login: "octo")
        rig.state.publishSyncState()
        await rig.sync()

        #expect(nodeNames(rig.lists) == ["remote"])
        #expect(rig.state.syncResult?.failure == nil)
        #expect(!rig.state.isSyncing)
    }

    @Test func theStatusShowsSyncingWhileGitHubIsBeingAsked() async {
        let github = FakeGitHub()
        github.setRemote(node("a"))
        let gate = Gate()
        github.configure { $0.gate = gate }
        let rig = Rig(github: github)

        rig.state.requestSync()
        await waitUntil { github.contentGets == 1 }
        #expect(rig.state.isSyncing)
        gate.release()
        await rig.state.syncTask?.value

        #expect(!rig.state.isSyncing)
    }

    // MARK: Failures

    @Test func aRevokedTokenIsForgottenAndTheUserIsToldToConnectAgain() async {
        let github = FakeGitHub()
        github.configure { $0.statusOverride = 401 }
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .unauthorized)
        #expect(rig.state.syncResult?.failure?.message == "GitHub no longer accepts this sign-in. Connect again to keep syncing.")
        #expect(rig.tokens.current == nil)
        #expect(rig.state.syncAccountLogin == "octo")
    }

    @Test func aMissingTokenIsTheSameAsARevokedOne() async {
        let rig = Rig(github: FakeGitHub(), local: node("a"), tokens: FakeTokenStore(token: nil))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .unauthorized)
        #expect(rig.github.requests.isEmpty)
    }

    @Test func aKeychainThatCannotBeReadIsReportedAndNothingIsDeleted() async {
        let tokens = FakeTokenStore()
        tokens.failReads(with: .keychain("User interaction is not allowed."))
        let rig = Rig(github: FakeGitHub(), local: node("a"), tokens: tokens)

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .other)
        #expect(rig.state.syncResult?.failure?.message == "DevHub could not use the keychain: User interaction is not allowed.")
        #expect(tokens.deletions == 0)
        #expect(rig.state.log.map(\.entry.text).contains("GitHub sync: User interaction is not allowed."))
    }

    @Test func beingOfflineKeepsTheTokenTheBaseAndTheTimeOfTheLastSuccess() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()
        let success = rig.state.syncLastSuccessAt

        github.configure { $0.offline = true }
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .offline)
        #expect(rig.state.syncResult?.failure?.message == "Could not reach GitHub.")
        #expect(rig.state.syncLastSuccessAt == success)
        #expect(rig.tokens.current == "token-1")
        #expect(rig.ledger.snapshot.base == node("a"))

        github.configure { $0.offline = false }
        await rig.sync()

        #expect(rig.state.syncResult?.failure == nil)
        #expect(github.remoteLists == node("a", "b"))
    }

    @Test func aRateLimitIsRefusedButKeepsTheToken() async {
        let github = FakeGitHub()
        github.configure { $0.statusOverride = 403 }
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .refused)
        #expect(rig.state.syncResult?.failure?.message == "GitHub refused the request: rate limit")
        #expect(rig.tokens.current == "token-1")
    }

    @Test func aServerErrorKeepsTheToken() async {
        let github = FakeGitHub()
        github.configure { $0.statusOverride = 502 }
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .other)
        #expect(rig.tokens.current == "token-1")
    }

    @Test func everyFailureIsWrittenToTheOutputLog() async {
        let github = FakeGitHub()
        github.configure { $0.statusOverride = 403 }
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.log.map(\.entry.text).contains("GitHub sync: GitHub refused the request: rate limit"))
    }

    // MARK: Files DevHub must not overwrite

    @Test func aFileFromANewerDevHubIsNeverOverwritten() async {
        let github = FakeGitHub()
        github.setRemoteData(Data(#"{"format":"devhub-standard-packages","version":2,"lists":{}}"#.utf8))
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .newerFile)
        #expect(github.puts == 0)
        #expect(nodeNames(rig.lists) == ["a"])
    }

    @Test func entriesThatThisVersionCannotReadAreKeptByNotUploading() async {
        let github = FakeGitHub()
        github.setRemoteData(Data(#"{"format":"devhub-standard-packages","version":1,"lists":{"node":[{"name":"eslint","kind":"npmGlobal"}],"swift":[{"name":"x","kind":"y"}]}}"#.utf8))
        let rig = Rig(github: github, local: node("mine"))

        await rig.sync()

        #expect(github.puts == 0)
        #expect(nodeNames(rig.lists) == ["eslint", "mine"])
        #expect(rig.state.syncResult?.failure?.kind == .newerFile)
        #expect(rig.ledger.snapshot.base.isEmpty)
    }

    @Test func afterReadingEntriesItCannotUseTheNextSyncStillDoesNotUpload() async {
        let github = FakeGitHub()
        github.setRemoteData(Data(#"{"format":"devhub-standard-packages","version":1,"lists":{"node":[{"name":"eslint","kind":"npmGlobal"}],"swift":[{"name":"x","kind":"y"}]}}"#.utf8))
        let rig = Rig(github: github, local: node("mine"))
        await rig.sync()

        await rig.sync()

        #expect(github.puts == 0)
        #expect(nodeNames(rig.lists) == ["eslint", "mine"])
    }

    @Test func aFileThatIsNotAStandardPackagesFileIsNeverOverwritten() async {
        let github = FakeGitHub()
        github.setRemoteData(Data(#"{"hello":"world"}"#.utf8))
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.kind == .other)
        #expect(rig.state.syncResult?.failure?.message == "The file in the repository is not a DevHub standard packages file. Nothing was uploaded.")
        #expect(github.puts == 0)
    }

    @Test func aFileThatIsNotJSONIsNeverOverwritten() async {
        let github = FakeGitHub()
        github.setRemoteData(Data("hello".utf8))
        let rig = Rig(github: github, local: node("a"))

        await rig.sync()

        #expect(rig.state.syncResult?.failure?.message == "The file in the repository could not be read. Nothing was uploaded.")
        #expect(github.puts == 0)
    }

    // MARK: Lost settings

    @Test func listsThatWereLostAreRestoredFromGitHubAndNotEmptiedThere() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()
        let putsBefore = github.puts

        rig.values.standardPackages = StandardPackageLists()
        await rig.sync()

        #expect(nodeNames(rig.lists) == ["a", "b"])
        #expect(github.puts == putsBefore)
        #expect(github.remoteLists == node("a", "b"))
    }

    @Test func listsThatWereLostAfterAnEditThatSyncedAreStillRestored() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        await rig.sync()

        rig.values.standardPackages = StandardPackageLists()
        await rig.sync()

        #expect(nodeNames(rig.lists) == ["a", "b"])
        #expect(github.remoteLists == node("a", "b"))
    }

    @Test func listsThatWereLostAfterTakingTheListsOfAnotherMacAreStillRestored() async {
        let github = FakeGitHub()
        github.setRemote(node("a", "b"))
        let rig = Rig(github: github)
        await rig.sync()

        rig.values.standardPackages = StandardPackageLists()
        await rig.sync()

        #expect(nodeNames(rig.lists) == ["a", "b"])
        #expect(github.remoteLists == node("a", "b"))
    }

    @Test func listsThatTheUserEmptiedByHandAreEmptiedOnGitHubToo() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()

        rig.edit { $0 = StandardPackageLists() }
        await rig.sync()

        #expect(github.remoteLists?.isEmpty == true)
        #expect(rig.lists.isEmpty)
    }

    // MARK: Automatic switch

    @Test func withTheSwitchOffNothingHappensOnItsOwn() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"), automatic: false)

        rig.state.requestAutomaticSync()
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        rig.state.checkAfterWake()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(github.requests.isEmpty)
        #expect(rig.state.pushTask == nil)
    }

    @Test func syncNowWorksWithTheSwitchOff() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"), automatic: false)

        rig.state.syncNow()
        await waitUntil { github.puts == 1 }

        #expect(github.remoteLists == node("a"))
    }

    @Test func switchingTheSwitchBackOnSyncsAtOnce() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let rig = Rig(github: github, automatic: false)

        rig.setAutomatic(true)
        await waitUntil { nodeNames(rig.lists) == ["remote"] }

        #expect(nodeNames(rig.lists) == ["remote"])
    }

    @Test func theScheduledChecksStartWithASync() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let rig = Rig(github: github)

        rig.state.startScheduledChecks(checkNow: false)
        await waitUntil { nodeNames(rig.lists) == ["remote"] }

        #expect(nodeNames(rig.lists) == ["remote"])
        rig.state.stopScheduledChecks()
    }

    @Test func wakingTheMacSyncs() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let rig = Rig(github: github)

        rig.state.checkAfterWake()
        await waitUntil { nodeNames(rig.lists) == ["remote"] }

        #expect(nodeNames(rig.lists) == ["remote"])
    }

    @Test func nothingSyncsWithoutAnAccount() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"), connected: false)

        rig.state.requestAutomaticSync()
        rig.state.syncNow()
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(github.requests.isEmpty)
        #expect(rig.state.pushTask == nil)
        #expect(!rig.state.isSyncing)
    }

    // MARK: State

    @Test func theLedgerIsPublishedWhenTheSyncIsConfigured() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()

        let second = Rig(github: github, local: node("a"), connected: false, tokens: rig.tokens, suite: rig.suite)

        #expect(second.state.syncAccountLogin == "octo")
        #expect(second.state.syncResult == rig.state.syncResult)
        #expect(second.state.syncLastSuccessAt == rig.state.syncLastSuccessAt)
    }

    @Test func aSuccessfulSyncPublishesTheTimeFromTheClock() async {
        let rig = Rig(github: FakeGitHub(), local: node("a"))

        await rig.sync()

        #expect(rig.state.syncLastSuccessAt != nil)
        #expect(rig.state.syncResult?.at == rig.state.syncLastSuccessAt)
    }

    // MARK: Disconnecting

    @Test func disconnectingForgetsTheAccountButKeepsTheLists() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a", "b"))
        await rig.sync()

        await rig.state.disconnectGitHub()

        #expect(rig.state.syncAccountLogin == nil)
        #expect(rig.state.syncResult == nil)
        #expect(rig.tokens.current == nil)
        #expect(rig.ledger.snapshot == SyncLedger.Snapshot())
        #expect(nodeNames(rig.lists) == ["a", "b"])
    }

    @Test func afterDisconnectingNothingSyncsAndEditsScheduleNothing() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()
        let requests = github.requests.count

        await rig.state.disconnectGitHub()
        rig.state.requestAutomaticSync()
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(github.requests.count == requests)
        #expect(rig.state.pushTask == nil)
    }

    @Test func disconnectingStopsAnUploadThatWasWaiting() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("a"))
        await rig.sync()
        rig.edit { $0.add(["b"], kind: .npmGlobal, to: .node) }
        let putsBefore = github.puts

        await rig.state.disconnectGitHub()
        rig.pushGate.release()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(github.puts == putsBefore)
    }

    // MARK: Signing in

    private func deviceTransport(github: FakeGitHub, tokenAnswers: @escaping @Sendable (Int) -> HTTPResponse = { _ in response(200, ["access_token": "gho_new"]) }) -> RoutedTransport {
        let polls = Counter()
        return RoutedTransport(api: github) { request in
            if request.url?.path == "/login/device/code" {
                return response(200, ["device_code": "dev-1", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5])
            }
            return tokenAnswers(polls.next())
        }
    }

    @Test func signingInShowsTheCodeThenLinksTheAccountAndSyncs() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, local: node("eslint"), connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github))
        rig.pollGate.close()

        rig.state.connectGitHub()
        await waitUntil { if case .waiting = rig.state.signIn { true } else { false } }
        guard case let .waiting(info) = rig.state.signIn else { Issue.record("Expected a code"); return }
        #expect(info.userCode == "WDJB-MJHT")
        #expect(info.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(rig.state.syncAccountLogin == nil)

        rig.pollGate.release()
        await waitUntil { rig.state.syncAccountLogin == "octo" }
        await rig.state.syncTask?.value

        #expect(rig.state.signIn == .idle)
        #expect(rig.tokens.current == "gho_new")
        #expect(github.remoteLists == node("eslint"))
        #expect(rig.state.syncResult?.failure == nil)
    }

    @Test func aPendingApprovalIsPolledUntilTheUserApproves() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github) { $0 < 2 ? response(200, ["error": "authorization_pending"]) : response(200, ["access_token": "gho_new"]) })

        rig.state.connectGitHub()
        await waitUntil { rig.state.syncAccountLogin == "octo" }

        #expect(rig.tokens.current == "gho_new")
    }

    @Test func aFlowThatIsTurnedOffShowsAMessageAndWritesTheLog() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: RoutedTransport(api: github) { _ in response(200, ["error": "device_flow_disabled"]) })

        rig.state.connectGitHub()
        await waitUntil { if case .failed = rig.state.signIn { true } else { false } }

        #expect(rig.state.signIn == .failed("Device sign-in is turned off for the DevHub app on GitHub."))
        #expect(rig.state.log.map(\.entry.text).contains("GitHub sync: Device sign-in is turned off for the DevHub app on GitHub."))
        #expect(rig.state.syncAccountLogin == nil)
    }

    @Test func aFailedSignInCanBeDismissed() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: RoutedTransport(api: github) { _ in response(200, ["error": "device_flow_disabled"]) })
        rig.state.connectGitHub()
        await waitUntil { if case .failed = rig.state.signIn { true } else { false } }

        rig.state.dismissSignInFailure()

        #expect(rig.state.signIn == .idle)
    }

    @Test func dismissingDoesNotTouchASignInThatIsWaiting() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github))
        rig.pollGate.close()
        rig.state.connectGitHub()
        await waitUntil { if case .waiting = rig.state.signIn { true } else { false } }

        rig.state.dismissSignInFailure()

        if case .waiting = rig.state.signIn {} else { Issue.record("The waiting sign-in was dismissed") }
        rig.state.cancelSignIn()
    }

    @Test func aDeniedApprovalShowsAMessage() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github) { _ in response(200, ["error": "access_denied"]) })

        rig.state.connectGitHub()
        await waitUntil { if case .failed = rig.state.signIn { true } else { false } }

        #expect(rig.state.signIn == .failed("The sign-in was cancelled on GitHub."))
        #expect(rig.tokens.current == nil)
    }

    @Test func cancellingTheSignInSavesNothing() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github))
        rig.pollGate.close()

        rig.state.connectGitHub()
        await waitUntil { if case .waiting = rig.state.signIn { true } else { false } }
        rig.state.cancelSignIn()
        await waitUntil { rig.state.signIn == .idle }
        rig.pollGate.release()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(rig.state.signIn == .idle)
        #expect(rig.tokens.current == nil)
        #expect(rig.state.syncAccountLogin == nil)
    }

    @Test func aTokenThatCannotFindItsAccountIsThrownAway() async {
        let github = FakeGitHub()
        github.configure { $0.statusOverride = 401 }
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        rig.attach(transport: deviceTransport(github: github))

        rig.state.connectGitHub()
        await waitUntil { if case .failed = rig.state.signIn { true } else { false } }

        #expect(rig.tokens.current == nil)
        #expect(rig.state.syncAccountLogin == nil)
    }

    @Test func connectingAgainReplacesARevokedAccountAndSyncsFromScratch() async {
        let github = FakeGitHub()
        github.setRemote(node("remote"))
        let rig = Rig(github: github, local: node("mine"), tokens: FakeTokenStore(token: nil))
        rig.ledger.recordSuccess(base: node("old"), summary: SyncSummary(added: 0, removed: 0), at: Date())
        rig.attach(transport: deviceTransport(github: github))

        rig.state.connectGitHub()
        await waitUntil { rig.tokens.current == "gho_new" }
        await waitUntil { github.remoteLists == node("mine", "remote") }

        #expect(nodeNames(rig.lists) == ["mine", "remote"])
    }

    @Test func aSecondConnectWhileOneIsRunningIsIgnored() async {
        let github = FakeGitHub()
        let rig = Rig(github: github, connected: false, tokens: FakeTokenStore(token: nil))
        let transport = deviceTransport(github: github)
        rig.attach(transport: transport)
        rig.pollGate.close()

        rig.state.connectGitHub()
        await waitUntil { if case .waiting = rig.state.signIn { true } else { false } }
        rig.state.connectGitHub()
        rig.pollGate.release()
        await waitUntil { rig.state.syncAccountLogin == "octo" }

        let codeRequests = github.requests.count
        #expect(codeRequests >= 1)
    }
}
