import Foundation
import Testing
@testable import DevHubCore

@Suite struct DiscoveryTests {
    @Test func homebrewPrefixDependsOnTheMachine() {
        let appleSilicon = HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew"))
        let intel = HomebrewInstallation(executable: URL(filePath: "/usr/local/bin/brew"))

        #expect(appleSilicon.prefix.path == "/opt/homebrew")
        #expect(intel.prefix.path == "/usr/local")
    }

    @Test func findsNodeVersionsFromEveryManagerNewestFirst() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/npm")
        try home.makeExecutable(".nvm/versions/node/v25.6.1/bin/npm")
        try home.makeExecutable("Library/Application Support/fnm/node-versions/v22.0.0/installation/bin/npm")
        try home.makeExecutable(".volta/tools/image/node/20.1.0/bin/npm")
        try home.makeExecutable(".asdf/installs/nodejs/18.1.0/bin/npm")

        let found = NodeVersionDiscovery(home: home.url).installations()

        #expect(found.map(\.version) == ["25.6.1", "24.21.0", "22.0.0", "20.1.0", "18.1.0"])
        #expect(found.map(\.manager) == [.nvm, .nvm, .fnm, .volta, .asdf])
        #expect(found[0].binDirectory.path.hasSuffix(".nvm/versions/node/v25.6.1/bin"))
        #expect(found[2].npm.path.hasSuffix("fnm/node-versions/v22.0.0/installation/bin/npm"))
    }

    @Test func skipsNodeFoldersThatCannotRun() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/npm")
        try home.makeFolder(".nvm/versions/node/v18.0.0/bin")
        try home.makeFolder(".nvm/versions/node/alias")

        let found = NodeVersionDiscovery(home: home.url).installations()

        #expect(found.map(\.version) == ["24.21.0"])
    }

    @Test func findsNothingWhenNoNodeManagerIsInstalled() throws {
        let home = try TemporaryHome()
        defer { home.remove() }

        #expect(NodeVersionDiscovery(home: home.url).installations().isEmpty)
    }

    @Test func findsRubyVersionsFromEveryManagerNewestFirst() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rvm/rubies/ruby-3.3.12/bin/gem")
        try home.makeExecutable(".rbenv/versions/3.2.4/bin/gem")
        try home.makeExecutable(".rubies/ruby-3.1.2/bin/gem")
        try home.makeExecutable(".asdf/installs/ruby/3.0.6/bin/gem")

        let found = RubyVersionDiscovery(home: home.url).installations()

        #expect(found.map(\.version) == ["3.3.12", "3.2.4", "3.1.2", "3.0.6"])
        #expect(found.map(\.manager) == [.rvm, .rbenv, .chruby, .asdf])
    }

    @Test func skipsRubyAliasesAndOtherImplementations() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rvm/rubies/ruby-3.3.12/bin/gem")
        try home.makeExecutable(".rvm/rubies/jruby-9.4.0/bin/gem")
        try FileManager.default.createSymbolicLink(
            at: home.url.appending(path: ".rvm/rubies/default"),
            withDestinationURL: home.url.appending(path: ".rvm/rubies/ruby-3.3.12")
        )

        let found = RubyVersionDiscovery(home: home.url).installations()

        #expect(found.map(\.version) == ["3.3.12"])
    }

    @Test func rvmGemsLiveOutsideTheRubyFolder() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rvm/rubies/ruby-3.3.12/bin/gem")

        let ruby = try #require(RubyVersionDiscovery(home: home.url).installations().first)

        let gems = home.url.appending(path: ".rvm/gems/ruby-3.3.12").path
        #expect(ruby.gemEnvironment["GEM_HOME"] == gems)
        #expect(ruby.gemEnvironment["GEM_PATH"] == "\(gems):\(gems)@global")
    }

    @Test func rbenvKeepsGemsInsideTheRubyFolder() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rbenv/versions/3.2.4/bin/gem")

        let ruby = try #require(RubyVersionDiscovery(home: home.url).installations().first)

        #expect(ruby.gemEnvironment.isEmpty)
    }

    @Test func aSymlinkedAliasOfARubyFolderIsNotASecondInstallation() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rbenv/versions/3.2.2/bin/gem")
        try FileManager.default.createSymbolicLink(
            at: home.url.appending(path: ".rbenv/versions/3.2"),
            withDestinationURL: home.url.appending(path: ".rbenv/versions/3.2.2")
        )

        let found = RubyVersionDiscovery(home: home.url).installations()

        #expect(found.map(\.version) == ["3.2.2"])
    }
}

