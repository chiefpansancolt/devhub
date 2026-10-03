import Foundation
import Testing
@testable import DevHubCore

private func ledger(_ build: (VersionLedger.Snapshot) -> VersionLedger.Snapshot = { $0 }, seeded: Bool = true, baseline: Set<String> = []) -> VersionLedger.Snapshot {
    var snapshot = VersionLedger.Snapshot()
    snapshot.isSeeded = seeded
    snapshot.baseline = baseline
    return build(snapshot)
}

private func standardLists() -> StandardPackageLists {
    var lists = StandardPackageLists()
    lists.add(["eslint", "typescript"], kind: .npmGlobal, to: .node)
    lists.add(["rails"], kind: .gem, to: .ruby)
    return lists
}

@Suite struct StandardPackagePlannerTests {
    private func offers(
        versions: [Bucket: [String]] = [.node: ["26.1.0", "24.21.0"], .ruby: ["3.4.1"]],
        installed: [Bucket: [String: Set<String>]] = [.node: ["26.1.0": [], "24.21.0": ["eslint", "typescript"]], .ruby: ["3.4.1": []]],
        lists: StandardPackageLists = standardLists(),
        ledger: VersionLedger.Snapshot = ledger(baseline: ["node/24.21.0"]),
        disabled: Set<Bucket> = []
    ) -> [StandardOffer] {
        StandardPackagePlanner.offers(versions: versions, installed: installed, lists: lists, ledger: ledger, disabledBanners: disabled)
    }

    @Test func offersTheVersionsThatAreNewAndMissingPackages() {
        let result = offers()

        #expect(result.map(\.id) == ["node/26.1.0", "ruby/3.4.1"])
        #expect(result[0].missing.map(\.name) == ["eslint", "typescript"])
        #expect(result[1].missing.map(\.name) == ["rails"])
    }

    @Test func offersOnlyWhatIsMissing() {
        let result = offers(installed: [.node: ["26.1.0": ["eslint"]], .ruby: ["3.4.1": ["rails"]]])

        #expect(result.map(\.id) == ["node/26.1.0"])
        #expect(result[0].missing.map(\.name) == ["typescript"])
    }

    @Test func nothingIsOfferedBeforeTheFirstRunHasSeeded() {
        #expect(offers(ledger: ledger(seeded: false)).isEmpty)
    }

    @Test func aVersionThatExistedAtTheFirstRunIsNeverOffered() {
        #expect(offers(ledger: ledger(baseline: ["node/26.1.0", "ruby/3.4.1"])).isEmpty)
    }

    @Test func aDismissedVersionIsNotOfferedAgain() {
        let result = offers(ledger: ledger({ var copy = $0; copy.dismissed = ["node/26.1.0"]; return copy }))

        #expect(result.map(\.id) == ["ruby/3.4.1"])
    }

    @Test func aVersionThatWasNotScannedIsLeftOut() {
        let result = offers(installed: [.node: [:], .ruby: ["3.4.1": []]])

        #expect(result.map(\.id) == ["ruby/3.4.1"])
    }

    @Test func aToolWithAnEmptyListOffersNothing() {
        var lists = StandardPackageLists()
        lists.add(["rails"], kind: .gem, to: .ruby)

        #expect(offers(lists: lists).map(\.id) == ["ruby/3.4.1"])
    }

    @Test func aToolWithItsBannerTurnedOffOffersNothingWhileTheOtherStillDoes() {
        #expect(offers(disabled: [.node]).map(\.id) == ["ruby/3.4.1"])
        #expect(offers(disabled: [.ruby]).map(\.id) == ["node/26.1.0"])
        #expect(offers(disabled: [.node, .ruby]).isEmpty)
    }

    @Test func aCompleteVersionHasNoOffer() {
        let result = offers(installed: [.node: ["26.1.0": ["eslint", "typescript"]], .ruby: ["3.4.1": ["rails"]]])

        #expect(result.isEmpty)
    }
}

@Suite struct VersionLedgerTests {
    private func defaults() -> UserDefaults {
        let name = "devhub-tests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func startsEmptyAndUnseeded() {
        let ledger = VersionLedger(defaults: defaults())

        #expect(ledger.snapshot == VersionLedger.Snapshot())
    }

    @Test func seedsOnlyOnce() {
        let ledger = VersionLedger(defaults: defaults())

        ledger.seedIfNeeded(with: ["node/24.21.0"])
        ledger.seedIfNeeded(with: ["node/24.21.0", "node/26.1.0"])

        #expect(ledger.snapshot.baseline == ["node/24.21.0"])
        #expect(ledger.snapshot.isSeeded)
    }

    @Test func rememberesDismissalsAndNotificationsAcrossLaunches() {
        let store = defaults()
        let first = VersionLedger(defaults: store)
        first.seedIfNeeded(with: ["ruby/3.3.5"])
        first.dismiss("node/26.1.0")
        first.markNotified(["ruby/3.4.1"])

        let second = VersionLedger(defaults: store)

        #expect(second.snapshot.dismissed == ["node/26.1.0"])
        #expect(second.snapshot.notified == ["ruby/3.4.1"])
        #expect(second.snapshot.baseline == ["ruby/3.3.5"])
    }

    @Test func clearingTheDismissalsOfOneToolKeepsTheOther() {
        let ledger = VersionLedger(defaults: defaults())
        ledger.dismiss("node/26.1.0")
        ledger.dismiss("ruby/3.4.1")
        ledger.markNotified(["node/26.1.0", "ruby/3.4.1"])

        ledger.clearDismissals(for: .node)

        #expect(ledger.snapshot.dismissed == ["ruby/3.4.1"])
        #expect(ledger.snapshot.notified == ["ruby/3.4.1"])
    }

    @Test func keysUseTheToolAndTheVersion() {
        #expect(VersionLedger.key(.node, "26.1.0") == "node/26.1.0")
    }
}
