import Testing
@testable import DevHubCore

@Suite struct BucketTests {
    @Test func listsTheThreeBucketsInSidebarOrder() {
        #expect(Bucket.allCases == [.homebrew, .node, .ruby])
    }

    @Test func displayNamesMatchTheDesign() {
        #expect(Bucket.allCases.map(\.displayName) == ["Homebrew", "Node", "Ruby"])
    }

    @Test func rawValuesAreStableForTheHistoryLog() {
        #expect(Bucket.allCases.map(\.rawValue) == ["homebrew", "node", "ruby"])
    }
}
