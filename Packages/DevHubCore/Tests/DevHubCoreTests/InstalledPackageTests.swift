import Testing
@testable import DevHubCore

@Suite struct InstalledPackageTests {
    private func package(installed: String, available: String?) -> InstalledPackage {
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "webpack", group: "22.11.0", installedVersion: installed, availableUpdate: available)
    }

    @Test func aNewerVersionIsAnUpdate() {
        let result = package(installed: "5.5.4", available: "5.6.3")

        #expect(result.isOutdated)
        #expect(result.availableUpdate == "5.6.3")
    }

    @Test func anInstalledVersionAheadOfTheLatestIsNotOutdated() {
        #expect(!package(installed: "6.0.0", available: "5.9.0").isOutdated)
        #expect(!package(installed: "6.0.0-beta.1", available: "5.9.0").isOutdated)
        #expect(!package(installed: "2026.7.22", available: "2025.4.26").isOutdated)
    }

    @Test func aRevisionOfTheSameReleaseIsNotOutdated() {
        #expect(!package(installed: "2.47.0_1", available: "2.47.0").isOutdated)
    }

    @Test func noUpdateStaysNoUpdate() {
        #expect(!package(installed: "1.0.0", available: nil).isOutdated)
    }
}
