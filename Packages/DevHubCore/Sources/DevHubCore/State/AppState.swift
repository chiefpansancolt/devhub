import Foundation
import Observation

public enum PopoverMode: Sendable, Equatable {
    /// The first scan has not finished.
    case checking
    case upToDate
    case updates
    case updating
    /// An update ended with failed or skipped packages that the user has not dismissed.
    case summary
}

public enum MenuBarIconState: Sendable, Equatable {
    case upToDate
    case updates(count: Int)
    case updating(finished: Int, total: Int)
    case failed(count: Int)
}

@MainActor
@Observable
public final class AppState {
    public private(set) var isChecking = false
    public private(set) var results: [Bucket: ScanResult] = [:]
    public private(set) var lastChecked: Date?
    public private(set) var nextCheck: Date?
    public private(set) var session: UpdateSession?
    /// What the last update did, in order. Kept for the history log.
    public private(set) var lastOutcomes: [UpdateOutcome] = []
    /// Buckets that cannot be scanned, with the reason.
    public let setupProblems: [Bucket: String]

    private let scanners: [Bucket: any PackageScanner]
    private let updater: PackageUpdater
    private let checkInterval: Duration
    private let now: @Sendable () -> Date
    private var updateTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?

    public init(
        scanners: [Bucket: any PackageScanner],
        setupProblems: [Bucket: String] = [:],
        runner: CommandRunning,
        checkInterval: Duration = .seconds(4 * 60 * 60),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanners = scanners
        self.setupProblems = setupProblems
        self.updater = PackageUpdater(scanners: scanners, runner: runner)
        self.checkInterval = checkInterval
        self.now = now
    }

    public convenience init(toolchain: Toolchain, runner: CommandRunning = CommandRunner()) {
        self.init(scanners: toolchain.scanners(runner: runner), setupProblems: toolchain.setupProblems, runner: runner)
    }

    // MARK: Reading the state

    /// The buckets that can be scanned, in sidebar order.
    public var readyBuckets: [Bucket] {
        Bucket.allCases.filter { scanners[$0] != nil }
    }

    public func outdated(in bucket: Bucket) -> [InstalledPackage] {
        (results[bucket]?.packages ?? []).filter(\.isOutdated)
    }

    /// The outdated packages of a bucket, split by Node or Ruby version. Homebrew has a single group with no name.
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

    /// A bucket whose scan produced no packages and at least one issue.
    private var failedScanCount: Int {
        results.values.filter { $0.packages.isEmpty && !$0.issues.isEmpty }.count
    }

    public var popoverMode: PopoverMode {
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

    /// Scans every ready bucket. Each bucket's result appears as soon as that bucket is done.
    public func refresh(_ reason: ScanReason = .check) async {
        guard !isChecking, session?.isRunning != true else { return }
        isChecking = true
        defer { isChecking = false }

        await withTaskGroup(of: (Bucket, ScanResult).self) { group in
            for (bucket, scanner) in scanners {
                group.addTask { (bucket, await scanner.scan(reason)) }
            }
            for await (bucket, result) in group {
                results[bucket] = result
            }
        }

        lastChecked = now()
        nextCheck = now().addingTimeInterval(checkInterval.seconds)
    }

    public func startRefresh(_ reason: ScanReason = .check) {
        refreshTask = Task { await refresh(reason) }
    }

    /// Checks now, then again after every interval, until `stopScheduledChecks()` is called.
    public func startScheduledChecks() {
        scheduleTask?.cancel()
        let interval = checkInterval
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopScheduledChecks() {
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    // MARK: Updating

    public func updateAll() async {
        await update(allOutdated)
    }

    /// Updates the given packages, then scans again. Cancelling the task, or calling `cancelUpdate()`, stops after the running package.
    public func update(_ packages: [InstalledPackage]) async {
        guard !packages.isEmpty, session?.isRunning != true else { return }
        session = UpdateSession(items: packages.map { UpdateItem(package: $0) }, isRunning: true)

        lastOutcomes = await updater.update(packages) { [weak self] id, status in
            await self?.setStatus(of: id, to: status)
        }
        session?.isRunning = false

        // A cancelled task cannot run the scan, so the scan starts in a task of its own.
        if Task.isCancelled {
            startRefresh(.afterUpdate)
        } else {
            await refresh(.afterUpdate)
        }
        if session?.endedWithoutProblems == true {
            session = nil
        }
    }

    public func startUpdate(_ packages: [InstalledPackage]) {
        updateTask = Task { await update(packages) }
    }

    public func startUpdateAll() {
        startUpdate(allOutdated)
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

    private func setStatus(of id: String, to status: UpdateStatus) {
        guard let index = session?.items.firstIndex(where: { $0.id == id }) else { return }
        session?.items[index].status = status
    }
}

extension Duration {
    fileprivate var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
