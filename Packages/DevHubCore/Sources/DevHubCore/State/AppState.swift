import Foundation
import Observation

extension Bucket {
    var checkCommandText: String {
        switch self {
        case .homebrew: "brew outdated --json=v2"
        case .node: "npm outdated -g --json"
        case .ruby: "gem outdated"
        }
    }
}

public enum PopoverMode: Sendable, Equatable {
    case noTools
    case checking
    case upToDate
    case updates
    case updating
    case summary
}

public enum MenuBarIconState: Sendable, Equatable {
    case upToDate
    case updates(count: Int)
    case updating(finished: Int, total: Int)
    case failed(count: Int)
}

public struct LogLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let entry: LogEntry
}

public struct UninstallProgress: Sendable, Equatable {
    public let packageID: String
    public var status: UpdateStatus
}

@MainActor
@Observable
public final class AppState {
    public private(set) var isChecking = false
    public private(set) var results: [Bucket: ScanResult] = [:]
    public private(set) var lastChecked: Date?
    public private(set) var nextCheck: Date?
    public private(set) var session: UpdateSession?
    public private(set) var uninstallProgress: UninstallProgress?
    public private(set) var runningSince: Date?
    public private(set) var log: [LogLine] = []
    public private(set) var setupProblems: [Bucket: String]
    public private(set) var disabledBuckets: Set<Bucket> = []
    public let history: HistoryStore

    private static let logLimit = 2000

    private var scanners: [Bucket: any PackageScanner]
    private var knownVersions: [Bucket: [String]]
    private var actions: PackageActionRunner
    private let runner: CommandRunning
    private var nextLogID = 0
    private var checkInterval: Duration?
    private var settings: SettingsValues?
    private var scanAgainWhenDone = false
    private var notifier: (any NotificationSending)?
    private var notificationLedger: NotificationLedger?
    private var notificationOptions = NotificationOptions()
    private let now: @Sendable () -> Date
    private var updateTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?

    public init(
        scanners: [Bucket: any PackageScanner],
        setupProblems: [Bucket: String] = [:],
        versions: [Bucket: [String]] = [:],
        runner: CommandRunning,
        history: HistoryStore = HistoryStore(),
        notifier: (any NotificationSending)? = nil,
        notificationLedger: NotificationLedger? = nil,
        notificationOptions: NotificationOptions = NotificationOptions(),
        checkInterval: Duration? = .seconds(4 * 60 * 60),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanners = scanners
        self.setupProblems = setupProblems
        self.knownVersions = versions
        self.history = history
        self.notifier = notifier
        self.notificationLedger = notificationLedger
        self.notificationOptions = notificationOptions
        self.actions = PackageActionRunner(scanners: scanners, runner: runner)
        self.runner = runner
        self.checkInterval = checkInterval
        self.now = now
    }

    public convenience init(
        settings: SettingsValues,
        runner: CommandRunning = CommandRunner(),
        notifier: (any NotificationSending)? = nil,
        notificationLedger: NotificationLedger? = nil
    ) {
        let toolchain = Toolchain.detect(settings: settings)
        let history = HistoryStore(log: HistoryLog())
        history.includesOutput = settings.historyIncludesOutput
        history.retention = settings.historyRetention
        self.init(
            scanners: toolchain.scanners(runner: runner, options: ScannerOptions(settings)),
            setupProblems: toolchain.setupProblems,
            versions: [.node: toolchain.node.map(\.version), .ruby: toolchain.ruby.map(\.version)],
            runner: runner,
            history: history,
            notifier: notifier,
            notificationLedger: notificationLedger,
            notificationOptions: NotificationOptions(settings),
            checkInterval: settings.checkInterval.duration
        )
        self.settings = settings
        disabledBuckets = settings.disabledBuckets
    }

    // MARK: Settings

    public func apply(_ newSettings: SettingsValues) {
        let previous = settings
        settings = newSettings

        history.includesOutput = newSettings.historyIncludesOutput
        history.retention = newSettings.historyRetention
        notificationOptions = NotificationOptions(newSettings)
        checkInterval = newSettings.checkInterval.duration
        nextCheck = checkInterval.map { (lastChecked ?? now()).addingTimeInterval($0.seconds) }

        let toolchain = Toolchain.detect(settings: newSettings)
        scanners = toolchain.scanners(runner: runner, options: ScannerOptions(newSettings))
        actions = PackageActionRunner(scanners: scanners, runner: runner)
        knownVersions = [.node: toolchain.node.map(\.version), .ruby: toolchain.ruby.map(\.version)]
        setupProblems = toolchain.setupProblems
        disabledBuckets = newSettings.disabledBuckets
        results = results.filter { scanners[$0.key] != nil }

        if scheduleTask != nil, previous?.checkInterval != newSettings.checkInterval {
            startScheduledChecks(checkNow: false)
        }
        if let previous, previous.scanningFields != newSettings.scanningFields {
            if isChecking {
                scanAgainWhenDone = true
            } else {
                startRefresh()
            }
        }
    }

    // MARK: Reading the state

    public var toolsNeedingSetup: [(bucket: Bucket, reason: String)] {
        Bucket.allCases.compactMap { bucket in
            setupProblems[bucket].map { (bucket, $0) }
        }
    }

    public var enabledBuckets: [Bucket] {
        Bucket.allCases.filter { !disabledBuckets.contains($0) }
    }

    public var readyBuckets: [Bucket] {
        Bucket.allCases.filter { scanners[$0] != nil }
    }

    public func outdated(in bucket: Bucket) -> [InstalledPackage] {
        (results[bucket]?.packages ?? []).filter(\.isOutdated)
    }

    public func packages(in scope: PackageScope) -> [InstalledPackage] {
        (results[scope.bucket]?.packages ?? []).filter(scope.contains)
    }

    public func outdated(in scope: PackageScope) -> [InstalledPackage] {
        packages(in: scope).filter(\.isOutdated)
    }

    public func groupScopes(of bucket: Bucket) -> [PackageScope] {
        let seen = Set((results[bucket]?.packages ?? []).compactMap(\.group))
        let versions = (knownVersions[bucket] ?? []) + seen.subtracting(knownVersions[bucket] ?? []).sorted { PackageVersion($0) > PackageVersion($1) }
        return PackageScope.groups(of: bucket, versions: versions)
    }

    public func package(withID id: String) -> InstalledPackage? {
        results.values.lazy.flatMap(\.packages).first { $0.id == id }
    }

    public func updateCommandText(for package: InstalledPackage) -> String? {
        scanners[package.bucket]?.updateCommand(for: package)?.displayText
    }

    public func uninstallCommandText(for package: InstalledPackage) -> String? {
        scanners[package.bucket]?.uninstallCommand(for: package)?.displayText
    }

    public func outdatedGroups(in bucket: Bucket) -> [(group: String?, packages: [InstalledPackage])] {
        var groups: [(group: String?, packages: [InstalledPackage])] = []
        for package in outdated(in: bucket) {
            if let index = groups.firstIndex(where: { $0.group == package.group }) {
                groups[index].packages.append(package)
            } else {
                groups.append((package.group, [package]))
            }
        }
        return groups
    }

    public func issues(in bucket: Bucket) -> [ScanIssue] {
        results[bucket]?.issues ?? []
    }

    public var allOutdated: [InstalledPackage] {
        readyBuckets.flatMap { outdated(in: $0) }
    }

    public var totalOutdated: Int { allOutdated.count }

    public var hasChecked: Bool { lastChecked != nil }

    /// An update or an uninstall is running. Only one runs at a time because Homebrew locks its files.
    public var isBusy: Bool {
        session?.isRunning == true || uninstallProgress?.status == .updating
    }

    private var failedScanCount: Int {
        results.values.filter { $0.packages.isEmpty && !$0.issues.isEmpty }.count
    }

    public var popoverMode: PopoverMode {
        if enabledBuckets.isEmpty { return .noTools }
        if let session {
            return session.isRunning ? .updating : .summary
        }
        if !hasChecked { return .checking }
        return totalOutdated == 0 ? .upToDate : .updates
    }

    public var menuBarIcon: MenuBarIconState {
        if let session {
            if session.isRunning { return .updating(finished: session.finishedCount, total: session.items.count) }
            return .failed(count: session.failedCount + session.skippedCount)
        }
        if failedScanCount > 0 { return .failed(count: failedScanCount) }
        return totalOutdated == 0 ? .upToDate : .updates(count: totalOutdated)
    }

    public func status(of package: InstalledPackage) -> UpdateStatus? {
        session?.items.first { $0.id == package.id }?.status
    }

    // MARK: Checking

    public func refresh(_ reason: ScanReason = .check, trigger: HistoryTrigger = .manual) async {
        guard !isChecking, !isBusy else { return }
        isChecking = true
        defer { isChecking = false }

        let started = now()
        let clock = ContinuousClock()
        let begin = clock.now

        await withTaskGroup(of: (Bucket, ScanResult).self) { group in
            for (bucket, scanner) in scanners {
                group.addTask { (bucket, await scanner.scan(reason)) }
            }
            for await (bucket, result) in group {
                results[bucket] = result
            }
        }

        lastChecked = now()
        nextCheck = checkInterval.map { now().addingTimeInterval($0.seconds) }
        if reason == .check, !scanners.isEmpty {
            history.record(checkEntry(startedAt: started, trigger: trigger, duration: clock.now - begin))
        }
        if reason == .check, trigger == .automatic {
            await announceNewUpdates()
        }
        if scanAgainWhenDone {
            scanAgainWhenDone = false
            startRefresh()
        }
    }

    private func announceNewUpdates() async {
        guard notificationOptions.isOn, let notifier, let notificationLedger else { return }
        let outdated = allOutdated
        let plan = NotificationPlanner.plan(
            outdated: outdated,
            seenKeys: notificationLedger.seenKeys,
            isFirstCheck: !notificationLedger.isSeeded,
            frequency: notificationOptions.frequency,
            lastSummary: notificationLedger.lastSummary,
            now: now()
        )
        notificationLedger.record(plan, stillOutdated: Set(outdated.compactMap(NotificationPlanner.key)))
        if let notification = plan.notification {
            await notifier.send(notification, playSound: notificationOptions.playsSound)
        }
    }

    public func startRefresh(_ reason: ScanReason = .check, trigger: HistoryTrigger = .manual) {
        refreshTask = Task { await refresh(reason, trigger: trigger) }
    }

    public func startScheduledChecks(checkNow: Bool = true) {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            var isFirstRound = true
            while !Task.isCancelled {
                guard let self else { return }
                if checkNow || !isFirstRound {
                    await self.refresh(.check, trigger: .automatic)
                }
                isFirstRound = false
                guard let interval = self.checkInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func checkAfterWake() {
        startRefresh(.check, trigger: .automatic)
    }

    private func checkEntry(startedAt: Date, trigger: HistoryTrigger, duration: Duration) -> HistoryEntry {
        let issues = readyBuckets.flatMap { bucket in (results[bucket]?.issues ?? []).map { issue in
            issue.group.map { "\(bucket.displayName) \($0): \(issue.message)" } ?? "\(bucket.displayName): \(issue.message)"
        } }
        let found = totalOutdated
        let summary = String(localized: "\(found) updates found", bundle: .module)
        return HistoryEntry(
            timestamp: startedAt,
            action: .check,
            bucket: nil,
            package: nil,
            trigger: trigger,
            command: readyBuckets.map(\.checkCommandText).joined(separator: " · "),
            exitCode: issues.isEmpty ? 0 : 1,
            durationMs: duration.milliseconds,
            ok: issues.isEmpty,
            message: issues.isEmpty ? summary : issues[0],
            output: history.includesOutput ? (issues.isEmpty ? [summary] : issues) : nil
        )
    }

    public func stopScheduledChecks() {
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    // MARK: Updating

    public func updateAll() async {
        await update(allOutdated, trigger: .updateAll)
    }

    public func update(_ packages: [InstalledPackage], trigger: HistoryTrigger = .manual) async {
        guard !packages.isEmpty, !isBusy else { return }
        session = UpdateSession(items: packages.map { UpdateItem(package: $0) }, isRunning: true)

        let outcomes = await actions.update(packages) { [weak self] event in
            await self?.handle(event)
        }
        session?.isRunning = false
        runningSince = nil
        record(outcomes, trigger: trigger)

        // A cancelled task cannot run the scan, so the scan starts in a task of its own.
        if Task.isCancelled {
            startRefresh(.afterUpdate)
        } else {
            await refreshAfterAction()
        }
        if session?.endedWithoutProblems == true {
            session = nil
        }
    }

    public func startUpdate(_ packages: [InstalledPackage], trigger: HistoryTrigger = .manual) {
        updateTask = Task { await update(packages, trigger: trigger) }
    }

    public func startUpdateAll() {
        startUpdate(allOutdated, trigger: .updateAll)
    }

    public func cancelUpdate() {
        updateTask?.cancel()
    }

    public func retryFailed() {
        guard let session, !session.isRunning else { return }
        let failed = session.failedItems.map(\.package)
        self.session = nil
        startUpdate(failed)
    }

    public func dismissSession() {
        guard session?.isRunning == false else { return }
        session = nil
    }

    // MARK: Uninstalling

    public func uninstall(_ package: InstalledPackage) async {
        guard !isBusy else { return }
        uninstallProgress = UninstallProgress(packageID: package.id, status: .updating)
        runningSince = Date()

        let outcome = await actions.uninstall(package) { [weak self] event in
            await self?.handle(event)
        }
        runningSince = nil
        record([outcome], trigger: .manual)

        if case .failed = outcome.status {
            uninstallProgress?.status = outcome.status
            return
        }
        uninstallProgress = nil
        removeFromResults(package.id)
        await refreshAfterAction()
    }

    public func startUninstall(_ package: InstalledPackage) {
        Task { await uninstall(package) }
    }

    public func dismissUninstallFailure() {
        guard case .failed = uninstallProgress?.status else { return }
        uninstallProgress = nil
    }

    private func record(_ outcomes: [ActionOutcome], trigger: HistoryTrigger) {
        for outcome in outcomes {
            if let entry = HistoryEntry(outcome: outcome, trigger: trigger, includesOutput: history.includesOutput) {
                history.record(entry)
            }
        }
    }

    // MARK: Events from running commands

    private func refreshAfterAction() async {
        while isChecking, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
        await refresh(.afterUpdate)
    }

    private func applyUpdateInResults(_ id: String) {
        changeResults(containing: id) { packages in packages.map { $0.id == id ? $0.withUpdateApplied() : $0 } }
    }

    private func removeFromResults(_ id: String) {
        changeResults(containing: id) { packages in packages.filter { $0.id != id } }
    }

    private func changeResults(containing id: String, _ change: ([InstalledPackage]) -> [InstalledPackage]) {
        for (bucket, result) in results where result.packages.contains(where: { $0.id == id }) {
            results[bucket] = ScanResult(packages: change(result.packages), issues: result.issues)
        }
    }

    private func handle(_ event: ActionEvent) {
        switch event {
        case let .status(id, status):
            guard let index = session?.items.firstIndex(where: { $0.id == id }) else { return }
            session?.items[index].status = status
            runningSince = status == .updating ? Date() : nil
            if status == .done { applyUpdateInResults(id) }
        case let .log(entry):
            log.append(LogLine(id: nextLogID, entry: entry))
            nextLogID += 1
            if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        }
    }
}

extension Duration {
    fileprivate var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
