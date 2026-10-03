import Foundation
import Testing
@testable import DevHubCore

@Suite struct SyncLedgerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func defaults() -> UserDefaults {
        let name = "devhub-tests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func aNewLedgerIsNotConnected() {
        let snapshot = SyncLedger(defaults: defaults()).snapshot

        #expect(snapshot.login == nil)
        #expect(snapshot.base.isEmpty)
        #expect(snapshot.lastResult == nil)
        #expect(snapshot.lastSuccessAt == nil)
    }

    @Test func connectingRemembersTheAccountAndStartsWithAnEmptyBase() {
        let ledger = SyncLedger(defaults: defaults())
        ledger.recordSuccess(base: makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }, summary: SyncSummary(added: 1, removed: 0), at: now)

        ledger.connect(login: "octo")

        #expect(ledger.snapshot.login == "octo")
        #expect(ledger.snapshot.base.isEmpty)
        #expect(ledger.snapshot.lastResult == nil)
    }

    @Test func aSuccessKeepsTheBaseTheSummaryAndTheTime() {
        let ledger = SyncLedger(defaults: defaults())
        ledger.connect(login: "octo")
        let base = makeLists { $0.add(["eslint", "vercel"], kind: .npmGlobal, to: .node) }

        ledger.recordSuccess(base: base, summary: SyncSummary(added: 3, removed: 1), at: now)

        #expect(ledger.snapshot.base == base)
        #expect(ledger.snapshot.lastResult == .success(at: now, summary: SyncSummary(added: 3, removed: 1)))
        #expect(ledger.snapshot.lastSuccessAt == now)
        #expect(ledger.snapshot.lastResult?.failure == nil)
    }

    @Test func aFailureKeepsTheBaseAndTheTimeOfTheLastSuccess() {
        let ledger = SyncLedger(defaults: defaults())
        ledger.connect(login: "octo")
        let base = makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }
        ledger.recordSuccess(base: base, summary: SyncSummary(added: 1, removed: 0), at: now)

        ledger.recordFailure(kind: .offline, message: "Could not reach GitHub.", at: now.addingTimeInterval(60))

        #expect(ledger.snapshot.base == base)
        #expect(ledger.snapshot.lastSuccessAt == now)
        #expect(ledger.snapshot.lastResult == .failed(at: now.addingTimeInterval(60), kind: .offline, message: "Could not reach GitHub."))
        #expect(ledger.snapshot.lastResult?.summary == nil)
    }

    @Test func clearingForgetsEverything() {
        let ledger = SyncLedger(defaults: defaults())
        ledger.connect(login: "octo")
        ledger.recordSuccess(base: makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }, summary: SyncSummary(added: 1, removed: 0), at: now)

        ledger.clear()

        #expect(ledger.snapshot == SyncLedger.Snapshot())
    }

    @Test func theLedgerSurvivesARestart() {
        let suite = defaults()
        let first = SyncLedger(defaults: suite)
        first.connect(login: "octo")
        first.recordSuccess(base: makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }, summary: SyncSummary(added: 1, removed: 0), at: now)

        let second = SyncLedger(defaults: suite)

        #expect(second.snapshot == first.snapshot)
        #expect(second.snapshot.login == "octo")
    }

    @Test func storedDataThatCannotBeReadStartsOver() {
        let suite = defaults()
        suite.set(Data("not json".utf8), forKey: "syncLedger.v1")

        #expect(SyncLedger(defaults: suite).snapshot == SyncLedger.Snapshot())
    }

    @Test func theSyncSettingDefaultsToOnAndSurvivesAnOldSettingsBlob() throws {
        #expect(SettingsValues().syncStandardPackagesAutomatically)
        let old = try JSONDecoder().decode(SettingsValues.self, from: Data(#"{"notifyStandardPackages": true}"#.utf8))

        #expect(old.syncStandardPackagesAutomatically)
        var off = SettingsValues()
        off.syncStandardPackagesAutomatically = false
        let decoded = try JSONDecoder().decode(SettingsValues.self, from: JSONEncoder().encode(off))
        #expect(!decoded.syncStandardPackagesAutomatically)
    }

    @Test func theSyncSettingDoesNotTriggerARescan() {
        var changed = SettingsValues()
        changed.syncStandardPackagesAutomatically = false

        #expect(changed.scanningFields == SettingsValues().scanningFields)
    }

    @Test func theAccountsTabExists() {
        #expect(SettingsTab.allCases.contains(.accounts))
        #expect(SettingsTab(rawValue: "accounts") == .accounts)
    }
}
