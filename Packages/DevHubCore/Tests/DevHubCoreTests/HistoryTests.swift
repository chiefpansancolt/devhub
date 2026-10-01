import Foundation
import Testing
@testable import DevHubCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ iso: String) -> Date {
    try! Date.ISO8601FormatStyle().parse(iso)
}

private func entry(
    _ iso: String = "2026-10-01T09:41:12Z",
    action: HistoryAction = .update,
    bucket: Bucket? = .homebrew,
    package: String? = "git",
    ok: Bool = true,
    message: String? = nil
) -> HistoryEntry {
    HistoryEntry(
        timestamp: date(iso), action: action, bucket: bucket, package: package,
        fromVersion: "1.0", toVersion: "2.0", trigger: .manual, command: "brew upgrade git",
        exitCode: ok ? 0 : 1, durationMs: 1200, ok: ok, message: message, output: ["line"]
    )
}

@Suite struct HistoryEntryTests {
    @Test func roundTripsThroughOneLineOfJSON() throws {
        let original = entry()

        let data = try HistoryCoding.encoder().encode(original)
        let decoded = try HistoryCoding.decoder().decode(HistoryEntry.self, from: data)

        #expect(decoded == original)
        #expect(!String(decoding: data, as: UTF8.self).contains("\n"))
    }

    @Test func writesTheTimestampWithAnOffsetAndMilliseconds() throws {
        let data = try HistoryCoding.encoder().encode(entry())
        let text = String(decoding: data, as: UTF8.self)

        let stamp = try #require(text.range(of: #""timestamp":"[^"]+""#, options: .regularExpression)).lowerBound
        let written = String(text[stamp...].dropFirst(13).prefix(while: { $0 != "\"" }))
        #expect(written.hasPrefix("2026-10-01T"))
        #expect(written.contains("."))
        #expect(written.range(of: #"(Z|[+-]\d\d:\d\d)$"#, options: .regularExpression) != nil)
    }

    @Test func readsAStampWithoutMilliseconds() throws {
        let json = #"{"id":"6E1F0C2A-3B4D-4E5F-8A9B-0C1D2E3F4A5B","timestamp":"2026-10-01T09:41:12-04:00","action":"check","trigger":"automatic","command":"x","exitCode":0,"durationMs":5,"ok":true}"#

        let decoded = try HistoryCoding.decoder().decode(HistoryEntry.self, from: Data(json.utf8))

        #expect(decoded.timestamp == date("2026-10-01T13:41:12Z"))
        #expect(decoded.bucket == nil)
    }

    @Test func buildsAnEntryFromAnOutcome() {
        let package = InstalledPackage(bucket: .node, kind: .npmGlobal, name: "typescript", group: "22.0.0", installedVersion: "5.5.4", availableUpdate: "5.6.3")
        let command = ToolCommand(executable: URL(filePath: "/x/npm"), arguments: ["install", "-g", "typescript@latest"], environment: [:], context: "Node 22.0.0")
        let result = CommandResult(exitCode: 243, standardOutput: "", standardError: "npm error code EACCES", duration: .milliseconds(3100))
        let outcome = ActionOutcome(
            package: package, action: .update, command: command, result: result, status: .failed("npm error code EACCES"),
            startedAt: date("2026-10-01T09:37:58Z"), output: [LogEntry(kind: .error, text: "npm error code EACCES")]
        )

        let built = HistoryEntry(outcome: outcome, trigger: .updateAll, includesOutput: true)

        #expect(built?.action == .update)
        #expect(built?.bucket == .node)
        #expect(built?.group == "22.0.0")
        #expect(built?.fromVersion == "5.5.4")
        #expect(built?.toVersion == "5.6.3")
        #expect(built?.trigger == .updateAll)
        #expect(built?.command == "npm install -g typescript@latest  (Node 22.0.0)")
        #expect(built?.exitCode == 243)
        #expect(built?.durationMs == 3100)
        #expect(built?.ok == false)
        #expect(built?.message == "npm error code EACCES")
        #expect(built?.output == ["npm error code EACCES"])
    }

    @Test func leavesTheOutputOutAtTheActionsOnlyLevel() {
        let package = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "1")
        let outcome = ActionOutcome(
            package: package, action: .uninstall, command: nil, result: nil, status: .done,
            startedAt: date("2026-10-01T09:37:58Z"), output: [LogEntry(kind: .output, text: "removed")]
        )

        #expect(HistoryEntry(outcome: outcome, trigger: .manual, includesOutput: false)?.output == nil)
        #expect(HistoryEntry(outcome: outcome, trigger: .manual, includesOutput: false)?.toVersion == nil)
    }

    @Test func aCommandThatNeverStartedLeavesNoEntry() {
        let package = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "1")
        let outcome = ActionOutcome(package: package, action: .update, command: nil, result: nil, status: .skipped)

        #expect(HistoryEntry(outcome: outcome, trigger: .manual, includesOutput: true) == nil)
    }
}

@Suite struct HistoryLogTests {
    private func makeLog() throws -> (HistoryLog, TemporaryHome) {
        let home = try TemporaryHome()
        return (HistoryLog(fileURL: home.url.appending(path: "Logs/DevHub/history.jsonl")), home)
    }

    @Test func createsTheFolderAndWritesOneLinePerEntry() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }

        try await log.append(entry("2026-10-01T09:00:00Z", package: "git"))
        try await log.append(entry("2026-10-01T09:01:00Z", package: "wget"))

        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2)
        #expect(text.hasSuffix("\n"))
        #expect(await log.entryCount() == 2)
    }

    @Test func readsTheNewestEntriesFirst() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry("2026-10-01T09:00:00Z", package: "first"))
        try await log.append(entry("2026-10-01T09:01:00Z", package: "second"))
        try await log.append(entry("2026-10-01T09:02:00Z", package: "third"))

        #expect(await log.recentEntries().map(\.package) == ["third", "second", "first"])
        #expect(await log.recentEntries(limit: 2).map(\.package) == ["third", "second"])
    }

    @Test func skipsAHalfWrittenLastLine() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry(package: "git"))
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"action":"upd"#.utf8))
        try handle.close()

        #expect(await log.recentEntries().map(\.package) == ["git"])
        #expect(await log.entryCount() == 1)
    }

    @Test func aMissingFileGivesAnEmptyHistory() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }

        #expect(await log.recentEntries().isEmpty)
        #expect(await log.fileSize() == 0)
    }

    @Test func pruneRemovesOnlyOlderEntries() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry("2025-01-01T09:00:00Z", package: "old"))
        try await log.append(entry("2026-09-30T09:00:00Z", package: "recent"))

        let removed = try await log.prune(olderThan: date("2026-01-01T00:00:00Z"))

        #expect(removed == 1)
        #expect(await log.recentEntries().map(\.package) == ["recent"])
        try await log.append(entry("2026-10-01T09:00:00Z", package: "after"))
        #expect(await log.entryCount() == 2)
    }

    @Test func pruneLeavesTheFileAloneWhenNothingIsOld() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry("2026-09-30T09:00:00Z"))
        let before = await log.fileSize()

        #expect(try await log.prune(olderThan: date("2026-01-01T00:00:00Z")) == 0)
        #expect(await log.fileSize() == before)
    }

    @Test func clearEmptiesTheFile() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry())

        try await log.clear()

        #expect(await log.entryCount() == 0)
        #expect(await log.fileSize() == 0)
    }

    @Test func copiesTheFileToAnotherPlace() async throws {
        let (log, home) = try makeLog()
        defer { home.remove() }
        try await log.append(entry(package: "git"))
        let destination = home.url.appending(path: "export.jsonl")

        try await log.copy(to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == String(contentsOf: log.fileURL, encoding: .utf8))
    }
}

@Suite struct HistoryListingTests {
    private let now = date("2026-10-01T12:00:00Z")
    private let entries = [
        entry("2026-10-01T09:41:12Z", action: .check, bucket: nil, package: nil, message: "12 updates found"),
        entry("2026-10-01T09:38:47Z", action: .update, bucket: .homebrew, package: "git"),
        entry("2026-10-01T09:37:58Z", action: .update, bucket: .node, package: "typescript", ok: false, message: "EACCES"),
        entry("2026-09-30T18:19:03Z", action: .uninstall, bucket: .node, package: "serve"),
        entry("2026-09-20T10:00:00Z", action: .update, bucket: .ruby, package: "bundler"),
        entry("2026-08-01T10:00:00Z", action: .update, bucket: .homebrew, package: "ancient")
    ]

    private func names(action: HistoryActionFilter = .all, range: HistoryRange = .allTime, bucket: Bucket? = nil, search: String = "") -> [String] {
        HistoryListing.filter(entries, action: action, range: range, bucket: bucket, search: search, now: now, calendar: utc)
            .map { $0.package ?? "check" }
    }

    @Test func filtersByAction() {
        #expect(names(action: .updates) == ["git", "typescript", "bundler", "ancient"])
        #expect(names(action: .uninstalls) == ["serve"])
        #expect(names(action: .checks) == ["check"])
        #expect(names(action: .failed) == ["typescript"])
    }

    @Test func filtersByRange() {
        #expect(names(range: .today) == ["check", "git", "typescript"])
        #expect(names(range: .lastSevenDays) == ["check", "git", "typescript", "serve"])
        #expect(names(range: .lastThirtyDays) == ["check", "git", "typescript", "serve", "bundler"])
        #expect(names(range: .allTime).count == 6)
    }

    @Test func aBucketFilterLeavesOutChecksOfEveryBucket() {
        #expect(names(bucket: .node) == ["typescript", "serve"])
        #expect(!names(bucket: .homebrew).contains("check"))
    }

    @Test func searchesPackageAndMessage() {
        #expect(names(search: "TYPE") == ["typescript"])
        #expect(names(search: "12 updates") == ["check"])
        #expect(names(search: "  ") .count == 6)
    }

    @Test func groupsByDayKeepingTheOrder() {
        let days = HistoryListing.days(entries, calendar: utc)

        #expect(days.count == 4)
        #expect(days[0].entries.count == 3)
        #expect(days[0].day == date("2026-10-01T00:00:00Z"))
        #expect(days[1].entries.map(\.package) == ["serve"])
    }
}

@MainActor
@Suite struct HistoryStoreTests {
    @Test func showsAnEntryAtOnceAndWritesItToTheFile() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        let store = HistoryStore(log: log)

        store.record(entry(package: "git"))

        #expect(store.entries.map(\.package) == ["git"])
        #expect(store.totalCount == 1)
        await store.waitUntilWritten()
        #expect(await log.entryCount() == 1)
        #expect(store.fileSize > 0)
    }

    @Test func writesEntriesInTheOrderTheyWereRecorded() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        let store = HistoryStore(log: log)

        for index in 0..<50 {
            store.record(entry("2026-10-01T09:00:00Z", package: "p\(index)"))
        }
        await store.waitUntilWritten()

        let written = await log.recentEntries().map(\.package)
        #expect(written == (0..<50).reversed().map { "p\($0)" })
    }

    @Test func startUpRemovesEntriesPastTheRetentionThenReads() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        try await log.append(entry("2024-01-01T09:00:00Z", package: "old"))
        try await log.append(entry("2026-09-30T09:00:00Z", package: "recent"))
        let store = HistoryStore(log: log)
        store.retention = .thirtyDays

        await store.startUp(now: date("2026-10-01T12:00:00Z"))

        #expect(store.entries.map(\.package) == ["recent"])
        #expect(store.totalCount == 1)
    }

    @Test func foreverKeepsEverything() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        try await log.append(entry("2001-01-01T09:00:00Z", package: "ancient"))
        let store = HistoryStore(log: log)
        store.retention = .forever

        await store.startUp(now: date("2026-10-01T12:00:00Z"))

        #expect(store.entries.map(\.package) == ["ancient"])
    }

    @Test func clearEmptiesTheListAndTheFile() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        let store = HistoryStore(log: log)
        store.record(entry())

        await store.clear()

        #expect(store.entries.isEmpty)
        #expect(await log.entryCount() == 0)
    }

    @Test func withoutALogEntriesStayInMemory() {
        let store = HistoryStore()

        store.record(entry(package: "git"))

        #expect(store.entries.count == 1)
        #expect(store.fileURL == nil)
    }
}

@MainActor
@Suite struct AppStateHistoryTests {
    private let packages = [
        outdatedPackage("git"),
        outdatedPackage("typescript", bucket: .node, group: "22.0.0")
    ]

    private func state(_ machine: FakeMachine, history: HistoryStore = HistoryStore(), runner: CommandRunning? = nil) -> AppState {
        AppState(
            scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine), .node: FakeScanner(bucket: .node, machine: machine)],
            runner: runner ?? machine.runner,
            history: history
        )
    }

    @Test func aManualCheckIsRecordedWithTheNumberOfUpdates() async {
        let state = state(FakeMachine(packages: packages))

        await state.refresh()

        let check = state.history.entries.first
        #expect(state.history.entries.count == 1)
        #expect(check?.action == .check)
        #expect(check?.bucket == nil)
        #expect(check?.trigger == .manual)
        #expect(check?.ok == true)
        #expect(check?.message == "2 updates found")
        #expect(check?.command == "brew outdated --json=v2 · npm outdated -g --json")
    }

    @Test func aScheduledCheckIsRecordedAsAutomatic() async {
        let state = state(FakeMachine(packages: packages))

        await state.refresh(.check, trigger: .automatic)

        #expect(state.history.entries.first?.trigger == .automatic)
    }

    @Test func aScanAfterAnUpdateIsNotRecorded() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        await state.updateAll()

        #expect(state.history.entries.filter { $0.action == .check }.count == 1)
    }

    @Test func eachUpdateIsRecordedWithItsVersionsAndOutput() async throws {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        await state.updateAll()

        let updates = state.history.entries.filter { $0.action == .update }.sorted { $0.package! < $1.package! }
        let git = try #require(updates.first)
        #expect(updates.map(\.package) == ["git", "typescript"])
        #expect(git.trigger == .updateAll)
        #expect(git.fromVersion == "1.0")
        #expect(git.toVersion == "2.0")
        #expect(git.ok)
        #expect(git.command == "true update git")
        #expect(git.output == ["updated git"])
        #expect(updates[1].group == "22.0.0")
    }

    @Test func aSingleUpdateIsRecordedAsManual() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        await state.update([packages[0]])

        #expect(state.history.entries.first { $0.action == .update }?.trigger == .manual)
    }

    @Test func aFailedUpdateKeepsTheReasonAndTheErrorLines() async {
        let state = state(FakeMachine(packages: packages, failing: ["typescript"]))
        await state.refresh()

        await state.updateAll()

        let failed = state.history.entries.first { $0.package == "typescript" }
        #expect(failed?.ok == false)
        #expect(failed?.exitCode == 243)
        #expect(failed?.message == "npm error code EACCES")
        #expect(failed?.output == ["npm error code EACCES", "npm error permission denied"])
    }

    @Test func anUninstallIsRecorded() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        await state.uninstall(packages[0])

        let entry = state.history.entries.first { $0.action == .uninstall }
        #expect(entry?.package == "git")
        #expect(entry?.toVersion == nil)
        #expect(entry?.ok == true)
    }

    @Test func theActionsOnlyLevelLeavesTheOutputOut() async {
        let history = HistoryStore()
        history.includesOutput = false
        let state = state(FakeMachine(packages: packages), history: history)
        await state.refresh()

        await state.updateAll()

        #expect(state.history.entries.allSatisfy { $0.output == nil })
    }

    @Test func aCancelledUpdateRecordsOnlyTheOneThatStarted() async {
        let machine = FakeMachine(packages: packages)
        let hanging = state(machine, runner: HangingRunner())
        await hanging.refresh()

        let task = Task { await hanging.updateAll() }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await task.value

        let updates = hanging.history.entries.filter { $0.action == .update }
        #expect(updates.count == 2)
        #expect(updates.allSatisfy { $0.message == "Cancelled" && !$0.ok })
    }

    @Test func theEntriesAreInTheFileWithinAMoment() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let log = HistoryLog(fileURL: home.url.appending(path: "history.jsonl"))
        let state = state(FakeMachine(packages: packages), history: HistoryStore(log: log))

        await state.refresh()
        await state.update([packages[0]])
        await state.history.waitUntilWritten()

        #expect(await log.entryCount() == 2)
    }
}
