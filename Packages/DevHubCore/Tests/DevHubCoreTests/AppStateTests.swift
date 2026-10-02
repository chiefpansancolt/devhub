import Foundation
import Testing
@testable import DevHubCore

final class FakeMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var packages: [InstalledPackage]
    private var failing: Set<String>
    private var reasons: [ScanReason] = []

    init(packages: [InstalledPackage], failing: Set<String> = []) {
        self.packages = packages
        self.failing = failing
    }

    var scanReasons: [ScanReason] { lock.withLock { reasons } }

    func packages(in bucket: Bucket) -> [InstalledPackage] {
        lock.withLock { packages.filter { $0.bucket == bucket } }
    }

    func add(_ package: InstalledPackage) {
        lock.withLock { packages.append(package) }
    }

    func recordScan(_ reason: ScanReason) {
        lock.withLock { reasons.append(reason) }
    }

    func runUpdate(of name: String) -> CommandResult {
        lock.withLock {
            if failing.contains(name) {
                return CommandResult(exitCode: 243, standardOutput: "", standardError: "npm error code EACCES\nnpm error permission denied")
            }
            packages = packages.map { $0.name == name ? $0.withUpdate(nil, isPinned: false) : $0 }
            return CommandResult(exitCode: 0, standardOutput: "updated \(name)", standardError: "")
        }
    }

    func runUninstall(of name: String) -> CommandResult {
        lock.withLock {
            if failing.contains(name) {
                return CommandResult(exitCode: 1, standardOutput: "", standardError: "Error: Refusing to uninstall \(name)")
            }
            packages.removeAll { $0.name == name }
            return CommandResult(exitCode: 0, standardOutput: "removed \(name)", standardError: "")
        }
    }

    var runner: FakeRunner {
        FakeRunner { [self] command in
            guard let verb = command.arguments.first, let name = command.arguments.last else {
                return failed(exitCode: 1, standardError: "unexpected command")
            }
            switch verb {
            case "update": return runUpdate(of: name)
            case "uninstall": return runUninstall(of: name)
            default: return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
    }
}

struct FakeScanner: PackageScanner {
    let bucket: Bucket
    let machine: FakeMachine

    func scan(_ reason: ScanReason) async -> ScanResult {
        machine.recordScan(reason)
        return ScanResult(packages: machine.packages(in: bucket))
    }

    func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == bucket else { return nil }
        return ToolCommand(executable: URL(filePath: "/usr/bin/true"), arguments: ["update", package.name], environment: [:])
    }

    func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == bucket else { return nil }
        return ToolCommand(executable: URL(filePath: "/usr/bin/true"), arguments: ["uninstall", package.name], environment: [:])
    }
}

func outdatedPackage(_ name: String, bucket: Bucket = .homebrew, group: String? = nil) -> InstalledPackage {
    InstalledPackage(bucket: bucket, kind: bucket == .homebrew ? .formula : .npmGlobal, name: name, group: group, installedVersion: "1.0", availableUpdate: "2.0")
}

struct HangingRunner: CommandRunning {
    func run(_ command: ToolCommand) async throws -> CommandResult {
        try await Task.sleep(for: .seconds(60))
        return succeeded("")
    }

    func stream(_ command: ToolCommand) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            let wait = Task {
                try? await Task.sleep(for: .seconds(60))
                continuation.yield(.finished(exitCode: 0, duration: .zero))
                continuation.finish()
            }
            continuation.onTermination = { _ in wait.cancel() }
        }
    }
}

private actor StatusLog {
    private(set) var entries: [String] = []

    func add(_ id: String, _ status: UpdateStatus) {
        entries.append("\(id)=\(status)")
    }
}

@Suite struct PackageActionRunnerTests {
    private func updater(_ machine: FakeMachine, buckets: [Bucket] = [.homebrew, .node]) -> PackageActionRunner {
        PackageActionRunner(
            scanners: Dictionary(uniqueKeysWithValues: buckets.map { ($0, FakeScanner(bucket: $0, machine: machine) as any PackageScanner) }),
            runner: machine.runner
        )
    }

    @Test func updatesPackagesInOrderAndReportsEachStatus() async {
        let packages = [outdatedPackage("git"), outdatedPackage("wget")]
        let machine = FakeMachine(packages: packages)
        let log = StatusLog()

        let outcomes = await updater(machine).update(packages) { event in if case let .status(id, status) = event { await log.add(id, status) } }

        #expect(outcomes.map(\.status) == [.done, .done])
        #expect(outcomes.map(\.package.name) == ["git", "wget"])
        let entries = await log.entries
        #expect(entries == [
            "homebrew/-/formula/git=updating", "homebrew/-/formula/git=done",
            "homebrew/-/formula/wget=updating", "homebrew/-/formula/wget=done"
        ])
    }

    @Test func aFailureDoesNotStopTheNextPackage() async {
        let packages = [outdatedPackage("typescript", bucket: .node, group: "22.0.0"), outdatedPackage("pnpm", bucket: .node, group: "22.0.0")]
        let machine = FakeMachine(packages: packages, failing: ["typescript"])

        let outcomes = await updater(machine).update(packages) { _ in }

        #expect(outcomes[0].status == .failed("npm error code EACCES"))
        #expect(outcomes[1].status == .done)
        #expect(outcomes[0].result?.exitCode == 243)
    }

    @Test func runsTheBucketsSideBySideAndKeepsTheInputOrder() async {
        let packages = [outdatedPackage("git"), outdatedPackage("pnpm", bucket: .node, group: "22.0.0"), outdatedPackage("wget")]
        let machine = FakeMachine(packages: packages)

        let outcomes = await updater(machine).update(packages) { _ in }

        #expect(outcomes.map(\.package.name) == ["git", "pnpm", "wget"])
    }

    @Test func aPackageWithNoScannerFails() async {
        let package = outdatedPackage("rake", bucket: .ruby, group: "3.3.12")
        let machine = FakeMachine(packages: [package])

        let outcomes = await updater(machine, buckets: [.homebrew]).update([package]) { _ in }

        #expect(outcomes[0].status == .failed("DevHub has no way to update this package."))
        #expect(outcomes[0].command == nil)
    }

    @Test func cancellingMarksTheRemainingPackagesSkipped() async {
        let packages = [outdatedPackage("git"), outdatedPackage("wget"), outdatedPackage("fzf")]
        let machine = FakeMachine(packages: packages)
        let hanging = PackageActionRunner(scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine)], runner: HangingRunner())

        let task = Task { await hanging.update(packages) { _ in } }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let outcomes = await task.value

        #expect(outcomes.map(\.status) == [.skipped, .skipped, .skipped])
    }
}

@MainActor
@Suite struct AppStateTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private func state(
        _ machine: FakeMachine,
        buckets: [Bucket] = [.homebrew, .node],
        setupProblems: [Bucket: String] = [:],
        runner: CommandRunning? = nil
    ) -> AppState {
        let now = fixedNow
        return AppState(
            scanners: Dictionary(uniqueKeysWithValues: buckets.map { ($0, FakeScanner(bucket: $0, machine: machine) as any PackageScanner) }),
            setupProblems: setupProblems,
            runner: runner ?? machine.runner,
            checkInterval: .seconds(4 * 3600),
            now: { now }
        )
    }

    private let threePackages = [
        outdatedPackage("git"),
        outdatedPackage("typescript", bucket: .node, group: "22.0.0"),
        outdatedPackage("pnpm", bucket: .node, group: "20.0.0")
    ]

    @Test func startsInTheCheckingMode() {
        let state = state(FakeMachine(packages: threePackages))

        #expect(state.popoverMode == .checking)
        #expect(state.hasChecked == false)
        #expect(state.totalOutdated == 0)
    }

    @Test func refreshFillsTheResultsAndSetsTheTimes() async {
        let state = state(FakeMachine(packages: threePackages))

        await state.refresh()

        #expect(state.totalOutdated == 3)
        #expect(state.popoverMode == .updates)
        #expect(state.menuBarIcon == .updates(count: 3))
        #expect(state.lastChecked == fixedNow)
        #expect(state.nextCheck == fixedNow.addingTimeInterval(4 * 3600))
        #expect(state.isChecking == false)
    }

    @Test func isUpToDateWhenNothingIsOutdated() async {
        let current = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "2.0")
        let state = state(FakeMachine(packages: [current]))

        await state.refresh()

        #expect(state.popoverMode == .upToDate)
        #expect(state.menuBarIcon == .upToDate)
    }

    @Test func groupsOutdatedPackagesByNodeVersionInScanOrder() async {
        let state = state(FakeMachine(packages: threePackages))

        await state.refresh()

        let groups = state.outdatedGroups(in: .node)
        #expect(groups.map(\.group) == ["22.0.0", "20.0.0"])
        #expect(groups.map { $0.packages.map(\.name) } == [["typescript"], ["pnpm"]])
        #expect(state.outdatedGroups(in: .homebrew).map(\.group) == [nil])
    }

    @Test func leavesOutBucketsThatAreNotSetUp() async {
        let machine = FakeMachine(packages: threePackages)
        let state = state(machine, buckets: [.homebrew], setupProblems: [.ruby: "No Ruby version manager found."])

        await state.refresh()

        #expect(state.readyBuckets == [.homebrew])
        #expect(state.setupProblems[.ruby] == "No Ruby version manager found.")
        #expect(state.totalOutdated == 1)
    }

    @Test func aBucketThatFailedToScanShowsAsFailed() async {
        struct BrokenScanner: PackageScanner {
            let bucket = Bucket.ruby
            func scan(_ reason: ScanReason) async -> ScanResult {
                ScanResult(packages: [], issues: [ScanIssue(group: nil, message: "gem exited with code 1")])
            }
            func updateCommand(for package: InstalledPackage) -> ToolCommand? { nil }
            func uninstallCommand(for package: InstalledPackage) -> ToolCommand? { nil }
        }
        let machine = FakeMachine(packages: [])
        let state = AppState(scanners: [.ruby: BrokenScanner()], runner: machine.runner)

        await state.refresh()

        #expect(state.menuBarIcon == .failed(count: 1))
        #expect(state.issues(in: .ruby).map(\.message) == ["gem exited with code 1"])
    }

    @Test func updateAllUpdatesEverythingThenScansAgain() async {
        let machine = FakeMachine(packages: threePackages)
        let state = state(machine)
        await state.refresh()

        await state.updateAll()

        #expect(state.totalOutdated == 0)
        #expect(state.session == nil)
        #expect(state.popoverMode == .upToDate)
        #expect(state.history.entries.filter { $0.action == .update }.count == 3)
        #expect(machine.scanReasons.filter { $0 == .afterUpdate }.count == 2)
    }

    @Test func afterAFailureTheSummaryStaysUntilItIsDismissed() async {
        let machine = FakeMachine(packages: threePackages, failing: ["typescript"])
        let state = state(machine)
        await state.refresh()

        await state.updateAll()

        #expect(state.popoverMode == .summary)
        #expect(state.session?.doneCount == 2)
        #expect(state.session?.failedCount == 1)
        #expect(state.menuBarIcon == .failed(count: 1))
        #expect(state.totalOutdated == 1)

        state.dismissSession()
        #expect(state.session == nil)
        #expect(state.popoverMode == .updates)
    }

    @Test func updatingOnePackageLeavesTheOthersAlone() async {
        let machine = FakeMachine(packages: threePackages)
        let state = state(machine)
        await state.refresh()

        await state.update([threePackages[0]])

        #expect(state.totalOutdated == 2)
        #expect(state.outdated(in: .homebrew).isEmpty)
    }

    @Test func doesNotStartASecondUpdateWhileOneRuns() async {
        let machine = FakeMachine(packages: threePackages)
        let hanging = state(machine, runner: HangingRunner())
        await hanging.refresh()

        let first = Task { await hanging.updateAll() }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(hanging.popoverMode == .updating)

        await hanging.update([threePackages[0]])
        #expect(hanging.session?.items.count == 3)

        first.cancel()
        await first.value
    }

    @Test func cancellingEndsWithSkippedPackagesAndScansAgain() async {
        let machine = FakeMachine(packages: threePackages)
        let hanging = state(machine, runner: HangingRunner())
        await hanging.refresh()

        let task = Task { await hanging.updateAll() }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        try? await Task.sleep(for: .milliseconds(200))

        #expect(hanging.session?.isRunning == false)
        #expect(hanging.session?.skippedCount == 3)
        #expect(hanging.popoverMode == .summary)
        #expect(machine.scanReasons.contains(.afterUpdate))
    }

    @Test func retryRunsOnlyTheFailedPackages() async {
        let machine = FakeMachine(packages: threePackages, failing: ["typescript"])
        let state = state(machine)
        await state.refresh()
        await state.updateAll()

        state.retryFailed()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(state.session?.items.map(\.package.name) == ["typescript"])
    }

    @Test func reportsTheStatusOfEachPackageDuringAnUpdate() async {
        let machine = FakeMachine(packages: threePackages)
        let hanging = state(machine, runner: HangingRunner())
        await hanging.refresh()

        let task = Task { await hanging.updateAll() }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(hanging.status(of: threePackages[0]) == .updating)
        #expect(hanging.status(of: threePackages[1]) == .updating)
        #expect(hanging.status(of: threePackages[2]) == .waiting)
        task.cancel()
        await task.value
    }
}

@Suite struct ToolchainTests {
    @Test func listsAProblemForEveryBucketThatIsMissing() {
        let toolchain = Toolchain(homebrew: nil, node: [], ruby: [])

        #expect(Set(toolchain.setupProblems.keys) == [.homebrew, .node, .ruby])
        #expect(toolchain.scanners(runner: CommandRunner()).isEmpty)
    }

    @Test func buildsAScannerOnlyForTheBucketsThatAreThere() {
        let brew = HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew"))
        let toolchain = Toolchain(homebrew: brew, node: [], ruby: [])

        #expect(Set(toolchain.scanners(runner: CommandRunner()).keys) == [.homebrew])
        #expect(Set(toolchain.setupProblems.keys) == [.node, .ruby])
    }
}
