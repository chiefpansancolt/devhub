import Foundation
import Testing
@testable import DevHubCore

@Suite struct NpmParserTests {
    @Test func readsInstalledGlobalPackages() throws {
        let packages = try NpmParser.parseInstalled(Fixture.data("npm-ls-v24.11.1.json"))

        #expect(packages.count == 19)
        #expect(packages.map(\.name) == packages.map(\.name).sorted())
        #expect(packages.contains(NpmParser.GlobalPackage(name: "vercel", version: "50.37.3")))
    }

    @Test func readsOutdatedPackages() throws {
        let outdated = try NpmParser.parseOutdated(Fixture.data("npm-outdated-v24.21.0.json"))

        #expect(Set(outdated.keys) == ["@salesforce/cli", "npm", "vercel"])
        #expect(outdated["npm"] == NpmParser.OutdatedPackage(current: "11.19.0", latest: "12.2.0"))
    }

    @Test func readsTheLargerOutdatedList() throws {
        #expect(try NpmParser.parseOutdated(Fixture.data("npm-outdated-v24.11.1.json")).count == 17)
        #expect(try NpmParser.parseOutdated(Fixture.data("npm-outdated-v25.6.1.json")).count == 14)
    }

    @Test(arguments: ["", "  \n", "{}"])
    func everythingCurrentGivesAnEmptyList(output: String) throws {
        #expect(try NpmParser.parseOutdated(Data(output.utf8)).isEmpty)
    }

    @Test func noGlobalPackagesGivesAnEmptyList() throws {
        #expect(try NpmParser.parseInstalled(Data(#"{"name":"lib"}"#.utf8)).isEmpty)
        #expect(try NpmParser.parseInstalled(Data()).isEmpty)
    }

    @Test func skipsAnOutdatedEntryThatHasNoInstalledVersion() throws {
        let json = #"{"gone":{"wanted":"1.0.0","latest":"1.0.0"},"here":{"current":"1.0.0","latest":"2.0.0"}}"#

        let outdated = try NpmParser.parseOutdated(Data(json.utf8))

        #expect(Set(outdated.keys) == ["here"])
    }
}

@Suite struct GemParserTests {
    @Test func readsInstalledGems() throws {
        let entries = GemParser.parseList(try Fixture.text("gem-list-3.3.12.txt"))

        #expect(entries.count == 128)
        #expect(entries.first { $0.name == "actionview" } == GemParser.ListEntry(name: "actionview", versions: ["8.1.3.1"], defaultVersion: nil))
    }

    @Test func readsDefaultGemsAndGemsWithManyVersions() throws {
        let entries = GemParser.parseList(try Fixture.text("gem-list-3.3.12.txt"))

        let defaultOnly = try #require(entries.first { $0.name == "abbrev" })
        #expect(defaultOnly.versions.isEmpty)
        #expect(defaultOnly.defaultVersion == "0.1.2")
        #expect(defaultOnly.displayVersion == "0.1.2")

        let both = try #require(entries.first { $0.name == "base64" })
        #expect(both.versions == ["0.3.0"])
        #expect(both.defaultVersion == "0.2.0")
        #expect(both.displayVersion == "0.3.0")
    }

    @Test func displayVersionIsTheNewestInstalledVersion() {
        let entry = GemParser.ListEntry(name: "json", versions: ["2.15.2", "3.0.2", "2.9.1"], defaultVersion: "2.7.0")

        #expect(entry.displayVersion == "3.0.2")
    }

    @Test func readsOutdatedGems() throws {
        let entries = GemParser.parseOutdated(try Fixture.text("gem-outdated-3.3.12.txt"))

        #expect(entries.count == 56)
        #expect(entries.contains(GemParser.OutdatedEntry(name: "actionview", latest: "8.1.4")))
        #expect(entries.contains(GemParser.OutdatedEntry(name: "benchmark", latest: "0.5.0")))
    }

    @Test func ignoresWarningsFromStandardError() throws {
        let noise = try Fixture.text("gem-outdated-3.1.2.stderr.txt")

        #expect(GemParser.parseList(noise).isEmpty)
        #expect(GemParser.parseOutdated(noise).isEmpty)
    }

    @Test func ignoresLinesThatLookLikeAGemButAreNot() {
        let text = """
        *** LOCAL GEMS ***

        Error loading RubyGems plugin "/x/rubygems_plugin.rb": cannot load such file (LoadError)
        rake (13.2.1)
        """

        #expect(GemParser.parseList(text).map(\.name) == ["rake"])
    }

    @Test func readsAnOutdatedLineWithAPlatformNote() {
        let entries = GemParser.parseOutdated("nokogiri (1.16.0 < 1.18.0 [arm64-darwin])")

        #expect(entries == [GemParser.OutdatedEntry(name: "nokogiri", latest: "1.18.0")])
    }
}

@Suite struct GemPlatformTests {
    @Test func dropsThePlatformFromAnInstalledVersion() {
        let entries = GemParser.parseList("nokogiri (1.19.4 arm64-darwin)\nrake (13.3.0, 13.2.1)")

        #expect(entries.first { $0.name == "nokogiri" }?.displayVersion == "1.19.4")
        #expect(entries.first { $0.name == "rake" }?.displayVersion == "13.3.0")
    }

    @Test func keepsAMixOfPlainAndPlatformVersionsInOrder() {
        let entries = GemParser.parseList("nokogiri (1.19.4 arm64-darwin, 1.18.10 arm64-darwin, 1.17.0)")

        #expect(entries.first?.displayVersion == "1.19.4")
    }
}
