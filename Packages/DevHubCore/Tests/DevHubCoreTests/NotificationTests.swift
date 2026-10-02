import Foundation
import Testing
@testable import DevHubCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func pkg(_ name: String, from: String = "1.0.0", to: String = "1.1.0", bucket: Bucket = .homebrew) -> InstalledPackage {
    InstalledPackage(bucket: bucket, kind: bucket == .homebrew ? .formula : .npmGlobal, name: name, group: bucket == .homebrew ? nil : "22.0.0", installedVersion: from, availableUpdate: to)
}

private func plan(
    _ outdated: [InstalledPackage],
    seen: Set<String> = [],
    first: Bool = false,
    frequency: NotificationFrequency,
    lastSummary: Date? = nil,
    now: Date = Date(timeIntervalSince1970: 1_790_000_000)
) -> NotificationPlan {
    NotificationPlanner.plan(outdated: outdated, seenKeys: seen, isFirstCheck: first, frequency: frequency, lastSummary: lastSummary, now: now, calendar: utc)
}

@Suite struct NotificationPlannerTests {
    @Test func theFirstCheckOnlyRemembersWhatIsAlreadyOutOfDate() {
        let result = plan([pkg("git"), pkg("wget")], first: true, frequency: .everyUpdate)

        #expect(result.notification == nil)
        #expect(result.keysToRemember.count == 2)
    }

    @Test func aKeyNamesThePackageAndTheVersionItWouldUpdateTo() {
        #expect(NotificationPlanner.key(for: pkg("git", to: "2.0.0")) == "homebrew/-/formula/git@2.0.0")
        #expect(NotificationPlanner.key(for: InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "1")) == nil)
    }

    @Test func everyUpdateAnnouncesOnlyTheNewOnes() {
        let seen: Set<String> = [NotificationPlanner.key(for: pkg("git"))!]

        let result = plan([pkg("git"), pkg("wget"), pkg("fzf")], seen: seen, frequency: .everyUpdate)

        #expect(result.notification == UpdateNotification(title: "2 new updates", body: "wget, fzf"))
        #expect(result.keysToRemember.count == 2)
        #expect(result.sentSummaryAt == nil)
    }

    @Test func aSingleNewUpdateReadsInTheSingular() {
        let result = plan([pkg("git")], frequency: .everyUpdate)

        #expect(result.notification == UpdateNotification(title: "1 new update", body: "git"))
    }

    @Test func aLongListIsShortenedToThreeNames() {
        let many = (1...6).map { pkg("p\($0)") }

        let result = plan(many, frequency: .everyUpdate)

        #expect(result.notification?.title == "6 new updates")
        #expect(result.notification?.body == "p1, p2, p3 and 3 more")
    }

    @Test func aNewerVersionOfAnAlreadyAnnouncedPackageIsANewUpdate() {
        let seen: Set<String> = [NotificationPlanner.key(for: pkg("git", to: "1.1.0"))!]

        let result = plan([pkg("git", to: "1.2.0")], seen: seen, frequency: .everyUpdate)

        #expect(result.notification?.title == "1 new update")
    }

    @Test func nothingNewMeansNoNotification() {
        let seen: Set<String> = [NotificationPlanner.key(for: pkg("git"))!]

        let result = plan([pkg("git")], seen: seen, frequency: .everyUpdate)

        #expect(result.notification == nil)
        #expect(result.keysToRemember.isEmpty)
    }

    @Test func theDailySummaryCountsEverythingThatIsOutOfDate() {
        let seen: Set<String> = [NotificationPlanner.key(for: pkg("git"))!]

        let result = plan([pkg("git"), pkg("wget")], seen: seen, frequency: .dailySummary)

        #expect(result.notification == UpdateNotification(title: "2 updates available", body: "git, wget"))
        #expect(result.sentSummaryAt != nil)
    }

    @Test func theDailySummaryIsSentOnlyOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let earlierToday = now.addingTimeInterval(-3 * 3600)

        let same = plan([pkg("wget")], frequency: .dailySummary, lastSummary: earlierToday, now: now)
        let nextDay = plan([pkg("wget")], frequency: .dailySummary, lastSummary: now.addingTimeInterval(-26 * 3600), now: now)

        #expect(same.notification == nil)
        #expect(same.keysToRemember.isEmpty)
        #expect(nextDay.notification != nil)
    }

    @Test func majorOnlyIgnoresMinorUpdatesButRemembersThem() {
        let minor = pkg("git", from: "2.47.0", to: "2.56.0")
        let major = pkg("vercel", from: "50.1.0", to: "62.1.0", bucket: .node)

        let both = plan([minor, major], frequency: .majorVersionsOnly)
        let onlyMinor = plan([minor], frequency: .majorVersionsOnly)

        #expect(both.notification == UpdateNotification(title: "1 major update", body: "vercel"))
        #expect(onlyMinor.notification == nil)
        #expect(onlyMinor.keysToRemember.count == 1)
    }

    @Test func readsTheMajorNumberOfAVersion() {
        #expect(PackageVersion("2.47.0").major == 2)
        #expect(PackageVersion("v24.21.0").major == 24)
        #expect(PackageVersion("2025-09-09").major == 2025)
        #expect(PackageVersion("rc1").major == nil)
    }
}

@Suite struct NotificationLedgerTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "devhub-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func startsEmptyAndUnseeded() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = NotificationLedger(defaults: defaults)

        #expect(ledger.seenKeys.isEmpty)
        #expect(!ledger.isSeeded)
        #expect(ledger.lastSummary == nil)
    }

    @Test func remembersWhatAPlanAnnouncedAcrossLaunches() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sent = Date(timeIntervalSince1970: 1_790_000_000)

        NotificationLedger(defaults: defaults).record(
            NotificationPlan(notification: nil, keysToRemember: ["a@1", "b@2"], sentSummaryAt: sent),
            stillOutdated: ["a@1", "b@2"]
        )

        let reopened = NotificationLedger(defaults: defaults)
        #expect(reopened.seenKeys == ["a@1", "b@2"])
        #expect(reopened.isSeeded)
        #expect(reopened.lastSummary == sent)
    }

    @Test func forgetsUpdatesThatAreNoLongerOutOfDate() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = NotificationLedger(defaults: defaults)
        ledger.record(NotificationPlan(notification: nil, keysToRemember: ["a@1", "b@2"], sentSummaryAt: nil), stillOutdated: ["a@1", "b@2"])

        ledger.record(NotificationPlan(notification: nil, keysToRemember: [], sentSummaryAt: nil), stillOutdated: ["b@2"])

        #expect(ledger.seenKeys == ["b@2"])
    }
}

final class FakeNotifier: NotificationSending, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(UpdateNotification, Bool)] = []

    var notifications: [UpdateNotification] { lock.withLock { sent.map(\.0) } }
    var sounds: [Bool] { lock.withLock { sent.map(\.1) } }

    func send(_ notification: UpdateNotification, playSound: Bool) async {
        lock.withLock { sent.append((notification, playSound)) }
    }

    func requestAuthorization() async -> Bool { true }
    func authorization() async -> NotificationAuthorization { .allowed }
}

@MainActor
@Suite struct AppStateNotificationTests {
    private func makeState(
        _ machine: FakeMachine,
        notifier: FakeNotifier,
        options: NotificationOptions = NotificationOptions(isOn: true, frequency: .everyUpdate, playsSound: false)
    ) -> (AppState, NotificationLedger, String) {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let ledger = NotificationLedger(defaults: UserDefaults(suiteName: suite)!)
        let state = AppState(
            scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine)],
            runner: machine.runner,
            notifier: notifier,
            notificationLedger: ledger,
            notificationOptions: options
        )
        return (state, ledger, suite)
    }

    @Test func theFirstAutomaticCheckStaysSilentAndRemembersWhatIsOutOfDate() async {
        let notifier = FakeNotifier()
        let (state, ledger, suite) = makeState(FakeMachine(packages: [outdatedPackage("git")]), notifier: notifier)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications.isEmpty)
        #expect(ledger.isSeeded)
        #expect(ledger.seenKeys.count == 1)
    }

    @Test func aLaterAutomaticCheckAnnouncesAnUpdateThatAppearedMeanwhile() async {
        let notifier = FakeNotifier()
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let (state, _, suite) = makeState(machine, notifier: notifier)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await state.refresh(.check, trigger: .automatic)

        machine.add(outdatedPackage("wget"))
        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications == [UpdateNotification(title: "1 new update", body: "wget")])
    }

    @Test func aManualCheckNeverNotifies() async {
        let notifier = FakeNotifier()
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let (state, ledger, suite) = makeState(machine, notifier: notifier)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await state.refresh(.check, trigger: .automatic)

        machine.add(outdatedPackage("wget"))
        await state.refresh(.check, trigger: .manual)

        #expect(notifier.notifications.isEmpty)
        #expect(ledger.seenKeys.count == 1)
    }

    @Test func nothingIsSentWhenNotificationsAreOff() async {
        let notifier = FakeNotifier()
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let (state, _, suite) = makeState(machine, notifier: notifier, options: NotificationOptions(isOn: false))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await state.refresh(.check, trigger: .automatic)

        machine.add(outdatedPackage("wget"))
        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications.isEmpty)
    }

    @Test func theSoundSettingIsPassedOn() async {
        let notifier = FakeNotifier()
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let (state, _, suite) = makeState(machine, notifier: notifier, options: NotificationOptions(isOn: true, frequency: .everyUpdate, playsSound: true))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await state.refresh(.check, trigger: .automatic)

        machine.add(outdatedPackage("wget"))
        await state.refresh(.check, trigger: .automatic)

        #expect(notifier.sounds == [true])
    }

    @Test func newSettingsChangeWhatIsAnnounced() async {
        let notifier = FakeNotifier()
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let (state, _, suite) = makeState(machine, notifier: notifier)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await state.refresh(.check, trigger: .automatic)
        var settings = SettingsValues()
        settings.notifyAboutUpdates = false
        settings.brewPath = "/nonexistent/bin/brew"
        settings.nodeFolder = "/nonexistent/node"
        settings.rubyFolder = "/nonexistent/ruby"

        state.apply(settings)

        #expect(state.setupProblems[.homebrew] != nil)
        #expect(notifier.notifications.isEmpty)
    }

    @Test func notificationDefaultsAreOnWithADailySummaryAndNoSound() {
        let values = SettingsValues()

        #expect(values.notifyAboutUpdates)
        #expect(values.notificationFrequency == .dailySummary)
        #expect(!values.notificationSound)
    }
}

private struct FlakyScanner: PackageScanner {
    let inner: FakeScanner
    let fails: FailureSwitch

    var bucket: Bucket { inner.bucket }

    func scan(_ reason: ScanReason) async -> ScanResult {
        if fails.isOn { return ScanResult(packages: [], issues: [ScanIssue(group: nil, message: "offline")]) }
        return await inner.scan(reason)
    }

    func updateCommand(for package: InstalledPackage) -> ToolCommand? { inner.updateCommand(for: package) }
    func uninstallCommand(for package: InstalledPackage) -> ToolCommand? { inner.uninstallCommand(for: package) }
}

private final class FailureSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false

    var isOn: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
}

@MainActor
@Suite struct FailedScanNotificationTests {
    private func state(notifier: FakeNotifier, fails: FailureSwitch, ledger: NotificationLedger) -> AppState {
        let machine = FakeMachine(packages: [outdatedPackage("git"), outdatedPackage("typescript", bucket: .node, group: "22.11.0")])
        return AppState(
            scanners: [
                .homebrew: FakeScanner(bucket: .homebrew, machine: machine),
                .node: FlakyScanner(inner: FakeScanner(bucket: .node, machine: machine), fails: fails)
            ],
            runner: machine.runner,
            notifier: notifier,
            notificationLedger: ledger,
            notificationOptions: NotificationOptions(isOn: true, frequency: .everyUpdate, playsSound: false)
        )
    }

    @Test func aBucketThatFailedToScanDoesNotMakeItsUpdatesNewAgain() async {
        let suite = "devhub-tests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let fails = FailureSwitch()
        let notifier = FakeNotifier()
        let app = state(notifier: notifier, fails: fails, ledger: NotificationLedger(defaults: UserDefaults(suiteName: suite)!))
        await app.refresh(.check, trigger: .automatic)

        fails.isOn = true
        await app.refresh(.check, trigger: .automatic)
        fails.isOn = false
        await app.refresh(.check, trigger: .automatic)

        #expect(notifier.notifications.isEmpty)
    }

    @Test func theFirstCheckDoesNotSeedWhileABucketIsFailing() async {
        let suite = "devhub-tests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let fails = FailureSwitch()
        fails.isOn = true
        let ledger = NotificationLedger(defaults: UserDefaults(suiteName: suite)!)
        let app = state(notifier: FakeNotifier(), fails: fails, ledger: ledger)

        await app.refresh(.check, trigger: .automatic)

        #expect(!ledger.isSeeded)
    }
}
