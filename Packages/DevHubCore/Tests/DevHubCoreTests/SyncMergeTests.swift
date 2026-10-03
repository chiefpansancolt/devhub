import Foundation
import Testing
@testable import DevHubCore

@Suite struct SyncMergeTests {
    private func merged(base: [String], local: [String], remote: [String]) -> [String] {
        nodeNames(StandardListsMerge.merge(base: node(base), local: node(local), remote: node(remote)))
    }

    private func node(_ names: [String]) -> StandardPackageLists {
        makeLists { $0.add(names, kind: .npmGlobal, to: .node) }
    }

    @Test(arguments: [
        (inLocal: true, inRemote: true, inBase: true, kept: true),
        (inLocal: true, inRemote: true, inBase: false, kept: true),
        (inLocal: true, inRemote: false, inBase: false, kept: true),
        (inLocal: true, inRemote: false, inBase: true, kept: false),
        (inLocal: false, inRemote: true, inBase: false, kept: true),
        (inLocal: false, inRemote: true, inBase: true, kept: false),
        (inLocal: false, inRemote: false, inBase: true, kept: false),
        (inLocal: false, inRemote: false, inBase: false, kept: false)
    ])
    func theTruthTableOfOneEntry(inLocal: Bool, inRemote: Bool, inBase: Bool, kept: Bool) {
        let result = merged(base: inBase ? ["eslint"] : [], local: inLocal ? ["eslint"] : [], remote: inRemote ? ["eslint"] : [])

        #expect(result == (kept ? ["eslint"] : []))
    }

    @Test func aFirstSyncWithAnEmptyBaseIsAUnion() {
        #expect(merged(base: [], local: ["eslint", "vercel"], remote: ["prettier", "eslint"]) == ["eslint", "prettier", "vercel"])
    }

    @Test func aRemovalOnOneMacRemovesTheEntryOnTheOther() {
        #expect(merged(base: ["eslint", "serve"], local: ["eslint"], remote: ["eslint", "serve"]) == ["eslint"])
        #expect(merged(base: ["eslint", "serve"], local: ["eslint", "serve"], remote: ["eslint"]) == ["eslint"])
    }

    @Test func anAddOnOneMacAndARemovalOnTheOtherBothHappen() {
        #expect(merged(base: ["a", "b"], local: ["a", "b", "c"], remote: ["a"]) == ["a", "c"])
    }

    @Test func aListEmptiedOnOneMacEmptiesTheOther() {
        #expect(merged(base: ["a", "b"], local: [], remote: ["a", "b"]).isEmpty)
    }

    @Test func aNameIsMatchedByKindAndName() {
        let formula = makeLists { $0.add(["jq"], kind: .formula, to: .homebrew) }
        let cask = makeLists { $0.add(["jq"], kind: .cask, to: .homebrew) }

        let result = StandardListsMerge.merge(base: StandardPackageLists(), local: formula, remote: cask)

        #expect(result.entries(for: .homebrew).map(\.id) == ["formula/jq", "cask/jq"])
    }

    @Test func aRemovedFormulaDoesNotRemoveACaskWithTheSameName() {
        let both = makeLists { $0.add(["jq"], kind: .formula, to: .homebrew); $0.add(["jq"], kind: .cask, to: .homebrew) }
        let caskOnly = makeLists { $0.add(["jq"], kind: .cask, to: .homebrew) }

        let result = StandardListsMerge.merge(base: both, local: caskOnly, remote: both)

        #expect(result.entries(for: .homebrew).map(\.id) == ["cask/jq"])
    }

    @Test func everyToolIsMerged() {
        let local = makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node); $0.add(["rails"], kind: .gem, to: .ruby) }
        let remote = makeLists { $0.add(["ripgrep"], kind: .cargoTool, to: .rust); $0.add(["black"], kind: .pythonTool, to: .python) }

        let result = StandardListsMerge.merge(base: StandardPackageLists(), local: local, remote: remote)

        #expect(result.entries(for: .node).map(\.name) == ["eslint"])
        #expect(result.entries(for: .ruby).map(\.name) == ["rails"])
        #expect(result.entries(for: .rust).map(\.name) == ["ripgrep"])
        #expect(result.entries(for: .python).map(\.name) == ["black"])
    }

    @Test func mergingThreeEqualListsChangesNothing() {
        let same = node(["eslint", "vercel"])

        #expect(StandardListsMerge.merge(base: same, local: same, remote: same) == same)
    }

    @Test func theResultOfAFirstSyncDoesNotDependOnTheSide() {
        let one = node(["a", "b"])
        let two = node(["b", "c"])

        #expect(StandardListsMerge.merge(base: StandardPackageLists(), local: one, remote: two) == StandardListsMerge.merge(base: StandardPackageLists(), local: two, remote: one))
    }

    @Test func theResultIsSortedAndHasNoDuplicates() {
        #expect(merged(base: [], local: ["zeta", "alpha"], remote: ["Mid", "alpha"]) == ["alpha", "Mid", "zeta"])
    }

    @Test func anEmptyListAndAMissingListAreEqual() {
        var withEmptyList = node(["a"])
        withEmptyList.set([], for: .ruby)

        #expect(withEmptyList == node(["a"]))
        #expect(node(["a"]) != node(["a", "b"]))
        #expect(node(["a"]) != makeLists { $0.add(["a"], kind: .gem, to: .ruby) })
    }

    @Test func aMergeResultEqualsTheListsItWasBuiltFromAfterAFileRoundTrip() throws {
        let local = node(["eslint", "vercel"])
        let merged = StandardListsMerge.merge(base: local, local: local, remote: local)
        let data = try StandardListsFile.make(from: merged, tools: Set(Bucket.allCases), now: Date()).encoded()

        #expect(try StandardListsFile.decode(data).file.lists == merged)
        #expect(merged == local)
    }

    @Test func theSummaryCountsWhatChanges() {
        let summary = StandardListsMerge.summary(from: node(["a", "b"]), to: node(["b", "c", "d"]))

        #expect(summary == SyncSummary(added: 2, removed: 1))
        #expect(StandardListsMerge.summary(from: node(["a"]), to: node(["a"])).isEmpty)
    }

    @Test func theSummaryAddsUpOverTools() {
        let before = makeLists { $0.add(["eslint"], kind: .npmGlobal, to: .node) }
        let after = makeLists { $0.add(["rails"], kind: .gem, to: .ruby) }

        #expect(StandardListsMerge.summary(from: before, to: after) == SyncSummary(added: 1, removed: 1))
    }
}
