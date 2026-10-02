import Foundation
import Testing
@testable import DevHubCore

@Suite struct NodeEngineRangeTests {
    @Test(arguments: [
        (">=14", "24.11.1", true),
        (">=18.*", "18.20.4", true),
        (">= 22.12.0", "22.11.0", false),
        (">= 22.12.0", "22.12.0", true),
        ("^20.19.0 || ^22.13.0 || >=24", "22.11.0", false),
        ("^20.19.0 || ^22.13.0 || >=24", "22.13.1", true),
        ("^20.19.0 || ^22.13.0 || >=24", "20.18.0", false),
        ("^20.19.0 || ^22.13.0 || >=24", "24.0.0", true),
        ("^20.17.0 || >=22.9.0", "21.0.0", false),
        (">=24", "22.11.0", false),
        ("^18", "18.20.4", true),
        ("^18", "20.0.0", false),
        ("~20.1", "20.1.9", true),
        ("~20.1", "20.2.0", false),
        ("18.x", "18.5.0", true),
        ("18.x", "19.0.0", false),
        ("<21", "20.9.0", true),
        ("<21", "21.0.0", false),
        ("12 - 14", "14.9.0", true),
        ("12 - 14", "15.0.0", false),
        (">=16 <20", "18.0.0", true),
        (">=16 <20", "20.0.0", false),
        ("*", "10.0.0", true)
    ])
    func decidesWhetherANodeVersionIsAllowed(range: String, node: String, expected: Bool) {
        #expect(NodeEngineRange(range).allows(node) == expected)
    }

    @Test func allowsEveryVersionWhenTheRangeIsMissingOrUnreadable() {
        #expect(NodeEngineRange(nil).allows("18.20.4"))
        #expect(NodeEngineRange("").allows("18.20.4"))
        #expect(NodeEngineRange("not a range").allows("18.20.4"))
    }
}

@Suite struct PublishedVersionParserTests {
    @Test func readsAListOfVersions() throws {
        let json = #"[{"version":"9.1.0","engines.node":">=18"},{"version":"9.2.0"}]"#

        let versions = try NpmParser.parsePublishedVersions(Data(json.utf8))

        #expect(versions == [
            NpmParser.PublishedVersion(version: "9.1.0", nodeRange: ">=18"),
            NpmParser.PublishedVersion(version: "9.2.0", nodeRange: nil)
        ])
    }

    @Test func readsASingleVersionPrintedAsAnObject() throws {
        let versions = try NpmParser.parsePublishedVersions(Data(#"{"version":"9.1.0","engines.node":">=18"}"#.utf8))

        #expect(versions == [NpmParser.PublishedVersion(version: "9.1.0", nodeRange: ">=18")])
    }

    @Test func readsNothingAsNoVersions() throws {
        #expect(try NpmParser.parsePublishedVersions(Data("\n".utf8)).isEmpty)
    }
}

@Suite struct CappedNodeUpdateTests {
    private let node18 = NodeInstallation(version: "18.20.4", manager: .nvm, root: URL(filePath: "/home/.nvm/versions/node/v18.20.4"))

    private func scanner(installed: String, latest: String, published: String?) -> NodeScanner {
        let runner = FakeRunner { command in
            switch command.arguments.first {
            case "ls": return succeeded(#"{"dependencies":{"eslint":{"version":"\#(installed)"}}}"#)
            case "outdated":
                return CommandResult(exitCode: 1, standardOutput: #"{"eslint":{"current":"\#(installed)","wanted":"\#(latest)","latest":"\#(latest)"}}"#, standardError: "")
            case "view":
                guard let published else { return failed(exitCode: 1, standardError: "offline") }
                return succeeded(published)
            default: return failed(exitCode: 1, standardError: "unexpected command")
            }
        }
        return NodeScanner(installations: [node18], runner: runner)
    }

    private let eslintVersions = """
    [
      {"version":"9.1.0","engines.node":"^18.18.0 || ^20.9.0 || >=21.1.0"},
      {"version":"9.39.0","engines.node":"^18.18.0 || ^20.9.0 || >=21.1.0"},
      {"version":"10.0.0","engines.node":"^20.19.0 || ^22.13.0 || >=24"},
      {"version":"10.11.0-rc.1","engines.node":">=18"},
      {"version":"10.11.0","engines.node":"^20.19.0 || ^22.13.0 || >=24"}
    ]
    """

    @Test func picksTheHighestVersionThatTheNodeVersionAllows() async throws {
        let result = await scanner(installed: "9.0.0", latest: "10.11.0", published: eslintVersions).scan()
        let eslint = try #require(result.packages.first)

        #expect(eslint.availableUpdate == "9.39.0")
    }

    @Test func installsTheChosenVersionInsteadOfLatest() async throws {
        let target = scanner(installed: "9.0.0", latest: "10.11.0", published: eslintVersions)
        let eslint = try #require(await target.scan().packages.first)

        #expect(target.updateCommand(for: eslint)?.arguments == ["install", "-g", "eslint@9.39.0"])
    }

    @Test func hasNoUpdateWhenEveryNewerVersionNeedsANewerNode() async throws {
        let onlyNewer = """
        [{"version":"10.0.0","engines.node":"^20.19.0 || >=24"},{"version":"10.11.0","engines.node":"^20.19.0 || >=24"}]
        """
        let result = await scanner(installed: "9.39.0", latest: "10.11.0", published: onlyNewer).scan()

        #expect(try #require(result.packages.first).isOutdated == false)
    }

    @Test func usesLatestWhenItWorksWithTheNodeVersion() async throws {
        let allAllowed = #"[{"version":"9.1.0","engines.node":">=18"},{"version":"9.2.0","engines.node":">=18"}]"#
        let result = await scanner(installed: "9.0.0", latest: "9.2.0", published: allAllowed).scan()

        #expect(try #require(result.packages.first).availableUpdate == "9.2.0")
    }

    @Test func usesLatestWhenTheLookupFails() async throws {
        let result = await scanner(installed: "9.0.0", latest: "10.11.0", published: nil).scan()

        #expect(try #require(result.packages.first).availableUpdate == "10.11.0")
    }
}
