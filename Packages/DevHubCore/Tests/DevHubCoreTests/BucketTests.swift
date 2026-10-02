import Testing
@testable import DevHubCore

@Suite struct BucketTests {
    @Test func listsTheBucketsInSidebarOrder() {
        #expect(Bucket.allCases == [.homebrew, .node, .ruby, .rust])
    }

    @Test func displayNamesMatchTheDesign() {
        #expect(Bucket.allCases.map(\.displayName) == ["Homebrew", "Node", "Ruby", "Rust"])
    }

    @Test func rawValuesAreStableForTheHistoryLog() {
        #expect(Bucket.allCases.map(\.rawValue) == ["homebrew", "node", "ruby", "rust"])
    }
}
