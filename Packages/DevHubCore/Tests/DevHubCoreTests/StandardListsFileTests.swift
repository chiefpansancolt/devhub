import Foundation
import Testing
@testable import DevHubCore

private func lists(_ build: (inout StandardPackageLists) -> Void) -> StandardPackageLists {
    var lists = StandardPackageLists()
    build(&lists)
    return lists
}

private let exportDate = Date(timeIntervalSince1970: 1_790_000_000)

private let sample = lists {
    $0.add(["git", "jq"], kind: .formula, to: .homebrew)
    $0.add(["raycast"], kind: .cask, to: .homebrew)
    $0.add(["eslint", "typescript"], kind: .npmGlobal, to: .node)
    $0.add(["rails"], kind: .gem, to: .ruby)
    $0.add(["stable"], kind: .rustToolchain, to: .rust)
    $0.add(["hexyl"], kind: .cargoTool, to: .rust)
}

@Suite struct StandardListsFileTests {
    @Test func theFileKeepsEverythingThroughAWriteAndARead() throws {
        let file = StandardListsFile.make(from: sample, tools: Set(Bucket.allCases), now: exportDate)

        let decoded = try StandardListsFile.decode(file.encoded())

        #expect(decoded.file.lists == sample)
        #expect(decoded.skippedEntries == 0)
        #expect(abs(try #require(decoded.file.exportedAt).timeIntervalSince(exportDate)) < 1)
    }

    @Test func theWrittenFileNamesItsFormatAndVersionAndIsEasyToRead() throws {
        let text = String(decoding: try StandardListsFile.make(from: sample, tools: [.node], now: exportDate).encoded(), as: UTF8.self)

        #expect(text.contains(#""format" : "devhub-standard-packages""#))
        #expect(text.contains(#""version" : 1"#))
        #expect(text.contains("\n"))
        #expect(text.contains(#""name" : "eslint""#))
    }

    @Test func theKeysAreInAlphabeticalOrderSoAFileDiffsCleanly() throws {
        let text = String(decoding: try StandardListsFile.make(from: sample, tools: Set(Bucket.allCases), now: exportDate).encoded(), as: UTF8.self)

        func position(_ key: String) -> String.Index { text.range(of: "\"\(key)\"")!.lowerBound }

        #expect(position("exportedAt") < position("format"))
        #expect(position("format") < position("lists"))
        #expect(position("lists") < position("version"))
        #expect(position("homebrew") < position("node"))
        #expect(position("node") < position("ruby"))
    }

    @Test func theSameListsGiveTheSameFile() throws {
        let first = try StandardListsFile.make(from: sample, tools: Set(Bucket.allCases), now: exportDate).encoded()
        let second = try StandardListsFile.make(from: sample, tools: Set(Bucket.allCases), now: exportDate).encoded()

        #expect(first == second)
    }

    @Test func onlyTheChosenToolsAreWritten() throws {
        let file = StandardListsFile.make(from: sample, tools: [.node, .ruby], now: exportDate)

        #expect(StandardListsFile.tools(in: file.lists) == [.node, .ruby])
        #expect(file.lists.entries(for: .homebrew).isEmpty)
    }

    @Test func aToolWithAnEmptyListIsLeftOut() throws {
        let file = StandardListsFile.make(from: sample, tools: [.node, .python], now: exportDate)

        let text = String(decoding: try file.encoded(), as: UTF8.self)

        #expect(!text.contains("python"))
        #expect(StandardListsFile.tools(in: file.lists) == [.node])
    }

    @Test func toolsListedInTheOrderOfTheSidebar() {
        #expect(StandardListsFile.tools(in: sample) == [.homebrew, .node, .ruby, .rust])
    }

    @Test func entriesThatCannotBeUsedAreCountedAndTheRestIsKept() throws {
        let json = Data(#"""
        {"format":"devhub-standard-packages","version":1,"exportedAt":"2026-10-02T10:00:00.000-04:00",
         "lists":{
           "node":[{"name":"typescript","kind":"npmGlobal"},{"name":"--evil","kind":"npmGlobal"},{"name":"x","kind":"newKind"},{"kind":"npmGlobal"}],
           "swift":[{"name":"a","kind":"gem"},{"name":"b","kind":"gem"}],
           "ruby":[{"name":"rails","kind":"gem"},{"name":"rake","kind":"npmGlobal"}]}}
        """#.utf8)

        let decoded = try StandardListsFile.decode(json)

        #expect(decoded.file.lists.entries(for: .node).map(\.name) == ["typescript"])
        #expect(decoded.file.lists.entries(for: .ruby).map(\.name) == ["rails"])
        #expect(decoded.skippedEntries == 6)
    }

    @Test func aToolWhoseValueIsNotAListIsSkippedWithoutLosingTheOthers() throws {
        let json = Data(#"{"format":"devhub-standard-packages","version":1,"lists":{"node":"oops","ruby":[{"name":"rails","kind":"gem"}]}}"#.utf8)

        let decoded = try StandardListsFile.decode(json)

        #expect(decoded.file.lists.entries(for: .ruby).map(\.name) == ["rails"])
        #expect(decoded.file.lists.entries(for: .node).isEmpty)
    }

    @Test func aFileWithoutListsOrDateStillReads() throws {
        let decoded = try StandardListsFile.decode(Data(#"{"format":"devhub-standard-packages","version":1}"#.utf8))

        #expect(decoded.file.lists.isEmpty)
        #expect(decoded.file.exportedAt == nil)
        #expect(decoded.skippedEntries == 0)
    }

    @Test func aNewerFormatVersionIsRejectedWithItsNumber() {
        let json = Data(#"{"format":"devhub-standard-packages","version":2,"lists":{}}"#.utf8)

        #expect(throws: StandardListsFile.ReadError.newerVersion(2)) { try StandardListsFile.decode(json) }
    }

    @Test func aFileOfAnotherKindIsRejected() {
        #expect(throws: StandardListsFile.ReadError.notAStandardPackagesFile) {
            try StandardListsFile.decode(Data(#"{"format":"something-else","version":1}"#.utf8))
        }
        #expect(throws: StandardListsFile.ReadError.notAStandardPackagesFile) {
            try StandardListsFile.decode(Data(#"{"version":1,"lists":{}}"#.utf8))
        }
    }

    @Test func textThatIsNotJSONIsUnreadable() {
        #expect(throws: StandardListsFile.ReadError.unreadable) { try StandardListsFile.decode(Data("not json".utf8)) }
        #expect(throws: StandardListsFile.ReadError.unreadable) { try StandardListsFile.decode(Data("[1,2]".utf8)) }
        #expect(throws: StandardListsFile.ReadError.unreadable) { try StandardListsFile.decode(Data()) }
    }

    @Test func everyErrorHasAMessageForThePerson() {
        let errors: [StandardListsFile.ReadError] = [.unreadable, .notAStandardPackagesFile, .newerVersion(3)]

        #expect(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
        #expect(StandardListsFile.ReadError.newerVersion(3).errorDescription?.contains("3") == true)
    }
}

@Suite struct StandardListsImporterTests {
    private func decoded(_ lists: StandardPackageLists, skipped: Int = 0) -> StandardListsFile.Decoded {
        StandardListsFile.Decoded(file: StandardListsFile(exportedAt: nil, lists: lists), skippedEntries: skipped)
    }

    private let current = lists {
        $0.add(["typescript", "prettier"], kind: .npmGlobal, to: .node)
        $0.add(["rails"], kind: .gem, to: .ruby)
    }

    private let incoming = lists {
        $0.add(["typescript", "eslint"], kind: .npmGlobal, to: .node)
        $0.add(["rails"], kind: .gem, to: .ruby)
        $0.add(["git"], kind: .formula, to: .homebrew)
    }

    @Test func mergingAddsOnlyTheNamesThatAreNew() {
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .merge)

        let node = plan.tools.first { $0.bucket == .node }
        #expect(node?.toAdd.map(\.name) == ["eslint"])
        #expect(node?.alreadyThere.map(\.name) == ["typescript"])
        #expect(node?.toRemove.isEmpty == true)
        #expect(node?.resulting.map(\.name) == ["eslint", "prettier", "typescript"])
    }

    @Test func replacingSwapsTheListAndReportsWhatGoesAway() {
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .replace)

        let node = plan.tools.first { $0.bucket == .node }
        #expect(node?.resulting.map(\.name) == ["eslint", "typescript"])
        #expect(node?.toRemove.map(\.name) == ["prettier"])
        #expect(node?.toAdd.map(\.name) == ["eslint"])
    }

    @Test func onlyTheToolsInTheFileAreInThePlan() {
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .merge)

        #expect(plan.tools.map(\.bucket) == [.homebrew, .node, .ruby])
    }

    @Test func aToolWithNothingNewDoesNotChangeTheList() {
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .merge)

        #expect(plan.tools.first { $0.bucket == .ruby }?.changesTheList == false)
        #expect(plan.changedTools == [.homebrew, .node])
    }

    @Test func replacingChangesAListThatOnlyLosesNames() {
        let file = decoded(lists { $0.add(["typescript"], kind: .npmGlobal, to: .node) })

        let plan = StandardListsImporter.plan(for: file, into: current, mode: .replace)

        #expect(plan.changedTools == [.node])
        #expect(StandardListsImporter.plan(for: file, into: current, mode: .merge).changedTools.isEmpty)
    }

    @Test func applyingWritesOnlyTheChosenTools() {
        var target = current
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .merge)

        StandardListsImporter.apply(plan, tools: [.node], to: &target)

        #expect(target.entries(for: .node).map(\.name) == ["eslint", "prettier", "typescript"])
        #expect(target.entries(for: .homebrew).isEmpty)
        #expect(target.entries(for: .ruby) == current.entries(for: .ruby))
    }

    @Test func applyingAReplaceDropsTheOldNames() {
        var target = current
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: current, mode: .replace)

        StandardListsImporter.apply(plan, tools: Set(Bucket.allCases), to: &target)

        #expect(target.entries(for: .node).map(\.name) == ["eslint", "typescript"])
        #expect(target.entries(for: .homebrew).map(\.name) == ["git"])
    }

    @Test func theSkippedCountPassesThrough() {
        #expect(StandardListsImporter.plan(for: decoded(incoming, skipped: 12), into: current, mode: .merge).skippedEntries == 12)
    }

    @Test func mergingIntoEmptyListsAddsEverything() {
        let plan = StandardListsImporter.plan(for: decoded(incoming), into: StandardPackageLists(), mode: .merge)

        #expect(plan.tools.allSatisfy { $0.alreadyThere.isEmpty })
        #expect(plan.changedTools == [.homebrew, .node, .ruby])
    }

    @Test func sameNameAsAFormulaAndAsACaskAreDifferentEntries() {
        let existing = lists { $0.add(["docker"], kind: .formula, to: .homebrew) }
        let file = decoded(lists { $0.add(["docker"], kind: .cask, to: .homebrew) })

        let plan = StandardListsImporter.plan(for: file, into: existing, mode: .merge)

        #expect(plan.tools[0].toAdd.map(\.kind) == [.cask])
        #expect(plan.tools[0].resulting.count == 2)
    }
}
