import Foundation
import Testing
@testable import DevHubCore

@Suite struct StandardNameTests {
    @Test(arguments: ["typescript", "@angular/cli", "homebrew/cask/firefox", "node@22", "left_pad.js", "c++", "rubocop-rails"])
    func acceptsOrdinaryPackageNames(name: String) {
        #expect(StandardName.isValid(name))
    }

    @Test(arguments: ["", "-g", "--registry=https://example.com", "a b", "a;rm", "$(whoami)", "a|b", "a`b`", "näme", "a\nb", "a&b"])
    func rejectsNamesThatCouldActAsOptionsOrShellText(name: String) {
        #expect(!StandardName.isValid(name))
    }

    @Test func rejectsANameThatIsTooLong() {
        #expect(StandardName.isValid(String(repeating: "a", count: 214)))
        #expect(!StandardName.isValid(String(repeating: "a", count: 215)))
    }

    @Test func splitsPastedTextAtSpacesCommasAndNewLines() {
        #expect(StandardName.names(in: "typescript, eslint  prettier\nvercel,\n\nserve ") == ["typescript", "eslint", "prettier", "vercel", "serve"])
        #expect(StandardName.names(in: " , \n").isEmpty)
    }
}

@Suite struct StandardPackageListsTests {
    @Test func addingSortsDeduplicatesAndReportsInvalidNames() {
        var lists = StandardPackageLists()

        let invalid = lists.add(["typescript", "Eslint", "typescript", "--bad", "a b", "prettier"], kind: .npmGlobal, to: .node)

        #expect(lists.entries(for: .node).map(\.name) == ["Eslint", "prettier", "typescript"])
        #expect(invalid == ["--bad", "a b"])
    }

    @Test func homebrewKeepsFormulaeBeforeCasks() {
        var lists = StandardPackageLists()
        lists.add(["raycast", "firefox"], kind: .cask, to: .homebrew)
        lists.add(["jq", "git"], kind: .formula, to: .homebrew)

        #expect(lists.entries(for: .homebrew).map(\.id) == ["formula/git", "formula/jq", "cask/firefox", "cask/raycast"])
    }

    @Test func aKindThatDoesNotBelongToTheToolIsDropped() {
        var lists = StandardPackageLists()

        lists.add(["firefox"], kind: .cask, to: .node)
        lists.set([StandardEntry(name: "rake", kind: .gem), StandardEntry(name: "typescript", kind: .npmGlobal)], for: .node)

        #expect(lists.entries(for: .node).map(\.name) == ["typescript"])
    }

    @Test func theSameNameIsAllowedAsAFormulaAndAsACask() {
        var lists = StandardPackageLists()
        lists.add(["docker"], kind: .formula, to: .homebrew)
        lists.add(["docker"], kind: .cask, to: .homebrew)

        #expect(lists.entries(for: .homebrew).count == 2)
    }

    @Test func removingTakesOutOnlyThatEntry() {
        var lists = StandardPackageLists()
        lists.add(["a", "b"], kind: .gem, to: .ruby)

        lists.remove(StandardEntry(name: "a", kind: .gem), from: .ruby)

        #expect(lists.entries(for: .ruby).map(\.name) == ["b"])
    }

    @Test func rustHoldsToolchainsAndCargoTools() {
        var lists = StandardPackageLists()
        lists.add(["hexyl"], kind: .cargoTool, to: .rust)
        lists.add(["stable"], kind: .rustToolchain, to: .rust)

        #expect(lists.entries(for: .rust).map(\.kind) == [.rustToolchain, .cargoTool])
    }

    @Test func everyToolHasItsOwnList() {
        var lists = StandardPackageLists()
        lists.add(["typescript"], kind: .npmGlobal, to: .node)

        #expect(lists.entries(for: .ruby).isEmpty)
        #expect(!lists.isEmpty)
        #expect(StandardPackageLists().isEmpty)
    }

    @Test func survivesAnEncodeAndDecodeRound() throws {
        var lists = StandardPackageLists()
        lists.add(["git"], kind: .formula, to: .homebrew)
        lists.add(["raycast"], kind: .cask, to: .homebrew)
        lists.add(["black"], kind: .pythonTool, to: .python)

        let decoded = try JSONDecoder().decode(StandardPackageLists.self, from: JSONEncoder().encode(lists))

        #expect(decoded == lists)
    }

    @Test func decodingDropsWhatItCannotUse() throws {
        let json = Data(#"""
        {"node":[{"name":"typescript","kind":"npmGlobal"},{"name":"--evil","kind":"npmGlobal"},{"name":"x","kind":"notAKind"},{"kind":"npmGlobal"},{"name":"rake","kind":"gem"}],
         "swift":[{"name":"x","kind":"gem"}],"ruby":"oops"}
        """#.utf8)

        let lists = try JSONDecoder().decode(StandardPackageLists.self, from: json)

        #expect(lists.entries(for: .node).map(\.name) == ["typescript"])
        #expect(lists.entries(for: .ruby).isEmpty)
    }

    @Test func decodingSomethingElseGivesEmptyLists() throws {
        #expect(try JSONDecoder().decode(StandardPackageLists.self, from: Data("[1,2]".utf8)).isEmpty)
    }

    @Test func emptyListsAreLeftOutOfTheEncodedForm() throws {
        var lists = StandardPackageLists()
        lists.add(["a"], kind: .gem, to: .ruby)
        lists.set([], for: .node)

        let text = String(decoding: try JSONEncoder().encode(lists), as: UTF8.self)

        #expect(text.contains("ruby"))
        #expect(!text.contains("node"))
    }
}

@Suite struct StandardSettingsTests {
    @Test func aSettingsFileFromBeforeStandardPackagesStillLoads() throws {
        let old = Data(#"{"theme":"dark","excludedNodeManagers":["bun"]}"#.utf8)

        let settings = try JSONDecoder().decode(SettingsValues.self, from: old)

        #expect(settings.standardPackages.isEmpty)
        #expect(settings.disabledStandardBanners.isEmpty)
        #expect(!settings.notifyStandardPackages)
    }

    @Test func theListsSurviveTheSettingsRoundTrip() throws {
        var settings = SettingsValues()
        settings.standardPackages.add(["typescript", "eslint"], kind: .npmGlobal, to: .node)
        settings.notifyStandardPackages = true

        let decoded = try JSONDecoder().decode(SettingsValues.self, from: JSONEncoder().encode(settings))

        #expect(decoded.standardPackages.entries(for: .node).map(\.name) == ["eslint", "typescript"])
        #expect(decoded.notifyStandardPackages)
    }

    @Test func editingTheListsDoesNotScanAgain() {
        let base = SettingsValues()
        var edited = base
        edited.standardPackages.add(["typescript"], kind: .npmGlobal, to: .node)
        edited.disabledStandardBanners = ["node"]
        edited.notifyStandardPackages = true

        #expect(edited.scanningFields == base.scanningFields)
    }
}
