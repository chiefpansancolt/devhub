import Foundation
import Testing
@testable import DevHubCore

private func makeScript(_ home: TemporaryHome, _ path: String, body: String) throws -> String {
    try home.makeExecutable(path)
    let file = home.url.appending(path: path)
    try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
    return file.path
}

@MainActor
@Suite struct SettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func startsWithTheDefaults() {
        let store = SettingsStore(defaults: makeDefaults())

        #expect(store.values == SettingsValues())
        #expect(store.values.checkInterval == .everyFourHours)
        #expect(store.values.brewRefreshIndex)
        #expect(store.values.confirmUninstall)
    }

    @Test func savesEveryChangeAndReadsItBack() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.values.checkInterval = .daily
        store.values.nodeFolder = "/somewhere/node"
        store.values.excludedRubyVersions = ["3.1.2"]
        store.values.theme = .dark

        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.values.checkInterval == .daily)
        #expect(reopened.values.nodeFolder == "/somewhere/node")
        #expect(reopened.values.excludedRubyVersions == ["3.1.2"])
        #expect(reopened.values.theme == .dark)
    }

    @Test func aFileFromAnOlderVersionStillLoads() throws {
        let defaults = makeDefaults()
        defaults.set(Data(#"{"checkInterval":"hourly"}"#.utf8), forKey: "settings.v1")

        let store = SettingsStore(defaults: defaults)

        #expect(store.values.checkInterval == .hourly)
        #expect(store.values.brewIncludeCasks)
        #expect(store.values.historyRetention == .oneYear)
    }

    @Test func aValueThisVersionDoesNotKnowFallsBackToItsDefault() {
        let defaults = makeDefaults()
        defaults.set(Data(#"{"checkInterval":"every-minute","theme":"dark"}"#.utf8), forKey: "settings.v1")

        let store = SettingsStore(defaults: defaults)

        #expect(store.values.checkInterval == .everyFourHours)
        #expect(store.values.theme == .dark)
    }

    @Test func aDamagedFileGivesTheDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "settings.v1")

        #expect(SettingsStore(defaults: defaults).values == SettingsValues())
    }

    @Test func eachIntervalHasItsDuration() {
        #expect(CheckInterval.hourly.duration == .seconds(3600))
        #expect(CheckInterval.everyFourHours.duration == .seconds(14400))
        #expect(CheckInterval.daily.duration == .seconds(86400))
        #expect(CheckInterval.manual.duration == nil)
    }

    @Test func onlyScanningFieldsTriggerANewScan() {
        let base = SettingsValues()
        var interval = base
        interval.checkInterval = .hourly
        var theme = base
        theme.theme = .dark
        var cleanup = base
        cleanup.brewCleanupAfterUpdate = false
        var casks = base
        casks.brewIncludeCasks = false
        var node = base
        node.excludedNodeVersions = ["22.0.0"]

        #expect(interval.scanningFields == base.scanningFields)
        #expect(theme.scanningFields == base.scanningFields)
        #expect(cleanup.scanningFields == base.scanningFields)
        #expect(casks.scanningFields != base.scanningFields)
        #expect(node.scanningFields != base.scanningFields)
    }
}

@Suite struct ChosenFolderDiscoveryTests {
    @Test func readsANodeFolderTheWayFnmLaysItOut() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("versions/v22.0.0/installation/bin/npm")
        try home.makeExecutable("versions/v20.1.0/installation/bin/npm")

        let found = NodeVersionDiscovery(versionsFolder: home.url.appending(path: "versions")).installations()

        #expect(found.map(\.version) == ["22.0.0", "20.1.0"])
        #expect(found[0].manager == .custom)
        #expect(found[0].npm.path.hasSuffix("v22.0.0/installation/bin/npm"))
    }

    @Test func readsANodeFolderTheWayNvmLaysItOut() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/npm")

        let found = NodeVersionDiscovery(versionsFolder: home.url.appending(path: ".nvm/versions/node")).installations()

        #expect(found.map(\.version) == ["24.21.0"])
        #expect(found[0].manager == .nvm)
    }

    @Test func aChosenNodeFolderReplacesTheUsualSearch() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".nvm/versions/node/v24.21.0/bin/npm")
        try FileManager.default.createDirectory(at: home.url.appending(path: "empty"), withIntermediateDirectories: true)

        let found = NodeVersionDiscovery(home: home.url, versionsFolder: home.url.appending(path: "empty")).installations()

        #expect(found.isEmpty)
    }

    @Test func readsAnRvmFolderAndKnowsWhereItsGemsAre() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable(".rvm/rubies/ruby-3.3.12/bin/gem")

        let found = RubyVersionDiscovery(versionsFolder: home.url.appending(path: ".rvm/rubies")).installations()

        let gems = home.url.appending(path: ".rvm/gems/ruby-3.3.12").path
        #expect(found.map(\.version) == ["3.3.12"])
        #expect(found[0].manager == .rvm)
        #expect(found[0].gemEnvironment["GEM_HOME"] == gems)
        #expect(found[0].gemEnvironment["GEM_PATH"] == "\(gems):\(gems)@global")
    }

    @Test func readsAnUnknownRubyFolderWithoutGemFolders() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("rubies/3.2.4/bin/gem")

        let found = RubyVersionDiscovery(versionsFolder: home.url.appending(path: "rubies")).installations()

        #expect(found.map(\.version) == ["3.2.4"])
        #expect(found[0].manager == .custom)
        #expect(found[0].gemEnvironment.isEmpty)
    }
}

@Suite struct ToolchainSettingsTests {
    @Test func aChosenBrewFileIsUsed() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let brew = try makeScript(home, "custom/bin/brew", body: "echo hi")
        var settings = SettingsValues()
        settings.brewPath = brew

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.homebrew?.executable.path == brew)
        #expect(toolchain.homebrew?.prefix.path == home.url.appending(path: "custom").path)
    }

    @Test func aChosenBrewFileThatIsMissingMakesTheBucketNotSetUp() {
        var settings = SettingsValues()
        settings.brewPath = "/nonexistent/bin/brew"

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.homebrew == nil)
        #expect(toolchain.setupProblems[.homebrew] == "There is no brew program at /nonexistent/bin/brew.")
        #expect(toolchain.scanners(runner: CommandRunner())[.homebrew] == nil)
    }

    @Test func aChosenNodeFolderWithNoVersionsSaysSo() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeFolder("empty")
        var settings = SettingsValues()
        settings.nodeFolder = home.url.appending(path: "empty").path

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.node.isEmpty)
        #expect(toolchain.setupProblems[.node]?.hasPrefix("No Node versions were found in ") == true)
    }

    @Test func versionsTurnedOffAreLeftOutOfTheScan() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v22.0.0/bin/npm")
        try home.makeExecutable("node/v20.0.0/bin/npm")
        var settings = SettingsValues()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.excludedNodeVersions = ["20.0.0"]

        #expect(Toolchain.detect(settings: settings).node.map(\.version) == ["22.0.0"])
        #expect(Toolchain.detect(settings: settings, applyingExclusions: false).node.map(\.version) == ["22.0.0", "20.0.0"])
    }

    @Test func turningOffEveryVersionExplainsWhyTheBucketIsEmpty() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("ruby/ruby-3.3.12/bin/gem")
        var settings = SettingsValues()
        settings.rubyFolder = home.url.appending(path: "ruby").path
        settings.excludedRubyVersions = ["3.3.12"]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.ruby.isEmpty)
        #expect(toolchain.setupProblems[.ruby] == "Every Ruby version is turned off in Settings.")
    }

    @Test func theScannerOptionsFollowTheSettings() {
        var settings = SettingsValues()
        settings.brewRefreshIndex = false
        settings.brewIncludeCasks = false
        settings.brewIncludeSelfUpdatingCasks = true
        settings.brewCleanupAfterUpdate = false
        settings.nodeIncludeNpm = false
        settings.gemInstallDocumentation = true

        let options = ScannerOptions(settings)

        #expect(options.homebrew == HomebrewOptions(refreshIndexFirst: false, includeSelfUpdatingCasks: true, includeCasks: false, cleanupAfterUpdate: false))
        #expect(options.node == NodeOptions(includeNpm: false))
        #expect(options.ruby == RubyOptions(installDocumentation: true))
    }
}

@Suite struct ScannerOptionTests {
    private let installation = HomebrewInstallation(executable: URL(filePath: "/opt/homebrew/bin/brew"))
    private let runner = FakeRunner { command in
        switch command.arguments.first {
        case "info": succeeded((try? Fixture.text("brew-info-installed.json")) ?? "")
        case "outdated": succeeded((try? Fixture.text("brew-outdated.json")) ?? "")
        default: succeeded("")
        }
    }

    @Test func leavesCasksOutWhenTheyAreTurnedOff() async {
        let options = HomebrewOptions(refreshIndexFirst: false, includeCasks: false)

        let result = await HomebrewScanner(installation: installation, runner: runner, options: options).scan()

        #expect(result.packages.count == 6)
        #expect(result.packages.allSatisfy { $0.kind == .formula })
    }

    @Test func tellsHomebrewNotToCleanUpWhenTurnedOff() {
        let on = HomebrewScanner(installation: installation, runner: runner, options: HomebrewOptions(cleanupAfterUpdate: true))
        let off = HomebrewScanner(installation: installation, runner: runner, options: HomebrewOptions(cleanupAfterUpdate: false))
        let git = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "1")

        #expect(on.updateCommand(for: git)?.environment["HOMEBREW_NO_INSTALL_CLEANUP"] == nil)
        #expect(off.updateCommand(for: git)?.environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
    }

    @Test func asksGemToInstallDocumentationOnlyWhenTurnedOn() {
        let ruby = RubyInstallation(version: "3.3.12", manager: .rvm, root: URL(filePath: "/r"))
        let package = InstalledPackage(bucket: .ruby, kind: .gem, name: "rails", group: "3.3.12", installedVersion: "7")

        let quiet = RubyScanner(installations: [ruby], runner: runner, options: RubyOptions(installDocumentation: false))
        let full = RubyScanner(installations: [ruby], runner: runner, options: RubyOptions(installDocumentation: true))

        #expect(quiet.updateCommand(for: package)?.arguments == ["update", "rails", "--no-document"])
        #expect(full.updateCommand(for: package)?.arguments == ["update", "rails"])
    }
}

@Suite struct PathValidationTests {
    @Test func recognisesHomebrew() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let brew = try makeScript(home, "bin/brew", body: #"echo "Homebrew 9.9.9""#)

        let check = await PathValidation.homebrew(path: brew, runner: CommandRunner())

        #expect(check == .found("Homebrew 9.9.9"))
    }

    @Test func rejectsAMissingFile() async {
        let check = await PathValidation.homebrew(path: "/nonexistent/brew", runner: CommandRunner())

        #expect(check == .problem("Nothing was found at this path."))
    }

    @Test func rejectsAFileThatIsNotAProgram() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let file = home.url.appending(path: "notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let check = await PathValidation.homebrew(path: file.path, runner: CommandRunner())

        #expect(check == .problem("This file is not a program."))
    }

    @Test func rejectsAProgramThatIsNotBrew() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        let other = try makeScript(home, "bin/other", body: "echo something else")
        let failing = try makeScript(home, "bin/broken", body: "exit 3")

        #expect(await PathValidation.homebrew(path: other, runner: CommandRunner()) == .problem("This program did not run as brew."))
        #expect(await PathValidation.homebrew(path: failing, runner: CommandRunner()) == .problem("This program did not run as brew."))
    }

    @Test func countsTheVersionsInAFolder() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v22.0.0/bin/npm")
        try home.makeExecutable("node/v20.0.0/bin/npm")
        try home.makeExecutable("ruby/ruby-3.3.12/bin/gem")

        #expect(PathValidation.nodeFolder(path: home.url.appending(path: "node").path) == .found("2 versions found"))
        #expect(PathValidation.rubyFolder(path: home.url.appending(path: "ruby").path) == .found("1 version found"))
    }

    @Test func explainsAFolderThatDoesNotWork() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeFolder("empty")

        #expect(PathValidation.nodeFolder(path: "/nonexistent") == .problem("This folder does not exist."))
        #expect(PathValidation.nodeFolder(path: home.url.appending(path: "empty").path) == .problem("No Node versions were found in this folder."))
        #expect(PathValidation.rubyFolder(path: home.url.appending(path: "empty").path) == .problem("No Ruby versions were found in this folder."))
    }
}

@MainActor
@Suite struct AppStateSettingsTests {
    private func state(interval: Duration? = .seconds(3600)) -> (AppState, FakeMachine) {
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let state = AppState(
            scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine)],
            runner: machine.runner,
            checkInterval: interval
        )
        return (state, machine)
    }

    private func settings(brewPath: String? = "/nonexistent/bin/brew", interval: CheckInterval = .everyFourHours) -> SettingsValues {
        var values = SettingsValues()
        values.brewPath = brewPath
        values.checkInterval = interval
        values.nodeFolder = "/nonexistent/node"
        values.rubyFolder = "/nonexistent/ruby"
        values.rustPath = "/nonexistent/bin/rustup"
        values.pipxPath = "/nonexistent/bin/pipx"
        values.uvPath = "/nonexistent/bin/uv"
        return values
    }

    @Test func newSettingsReplaceTheScannersAndShowWhyABucketIsNotSetUp() async {
        let (state, _) = state()
        await state.refresh()
        #expect(state.totalOutdated == 1)

        state.apply(settings())

        #expect(state.readyBuckets.isEmpty)
        #expect(state.totalOutdated == 0)
        #expect(state.setupProblems[.homebrew] == "There is no brew program at /nonexistent/bin/brew.")
    }

    @Test func aChangeThatAffectsScansStartsANewScan() async throws {
        let (state, _) = state()
        state.apply(settings(brewPath: "/first/bin/brew"))
        await state.refresh()
        let before = try #require(state.lastChecked)
        try await Task.sleep(for: .milliseconds(20))

        state.apply(settings(brewPath: "/second/bin/brew"))
        try await Task.sleep(for: .milliseconds(300))

        #expect(try #require(state.lastChecked) > before)
    }

    @Test func aChangeThatDoesNotAffectScansLeavesTheLastCheckAlone() async throws {
        let (state, _) = state()
        state.apply(settings())
        await state.refresh()
        let before = try #require(state.lastChecked)

        state.apply(settings(interval: .daily))
        try await Task.sleep(for: .milliseconds(200))

        #expect(state.lastChecked == before)
    }

    @Test func theNextCheckFollowsTheInterval() async throws {
        let (state, _) = state()
        state.apply(settings())
        await state.refresh()
        let last = try #require(state.lastChecked)

        state.apply(settings(interval: .daily))
        #expect(state.nextCheck == last.addingTimeInterval(86400))

        state.apply(settings(interval: .manual))
        #expect(state.nextCheck == nil)
    }

    @Test func withNoIntervalTheScheduleChecksOnceAndStops() async throws {
        let (state, machine) = state(interval: nil)

        state.startScheduledChecks()
        try await Task.sleep(for: .milliseconds(300))

        #expect(machine.scanReasons == [.check])
        #expect(state.nextCheck == nil)
        state.stopScheduledChecks()
    }

    @Test func canStartTheScheduleWithoutCheckingAtOnce() async throws {
        let (state, machine) = state(interval: .seconds(3600))

        state.startScheduledChecks(checkNow: false)
        try await Task.sleep(for: .milliseconds(200))

        #expect(machine.scanReasons.isEmpty)
        state.stopScheduledChecks()
    }

    @Test func aCheckAfterWakeIsRecordedAsAutomatic() async throws {
        let (state, _) = state()

        state.checkAfterWake()
        try await Task.sleep(for: .milliseconds(300))

        #expect(state.history.entries.first?.trigger == .automatic)
    }

    @Test func historyOptionsFollowTheSettings() {
        let (state, _) = state()
        var values = settings()
        values.historyIncludesOutput = false
        values.historyRetention = .thirtyDays

        state.apply(values)

        #expect(!state.history.includesOutput)
        #expect(state.history.retention == .thirtyDays)
    }
}

@MainActor
@Suite struct TurnedOffToolsTests {
    @Test func everyToolIsOnByDefault() {
        #expect(SettingsValues().disabledBuckets.isEmpty)
    }

    @Test func theChoiceIsSavedAndReadBack() {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)

        store.values.disabledBuckets = [.ruby, .node]

        #expect(SettingsStore(defaults: defaults).values.disabledBuckets == [.ruby, .node])
    }

    @Test func aFileWithoutTheFieldLoadsWithEveryToolOn() {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"checkInterval":"daily"}"#.utf8), forKey: "settings.v1")

        #expect(SettingsStore(defaults: defaults).values.disabledBuckets.isEmpty)
    }

    @Test func turningAToolOnOrOffTriggersANewScan() {
        let base = SettingsValues()
        var off = base
        off.disabledBuckets = [.ruby]

        #expect(base.scanningFields != off.scanningFields)
    }

    @Test func aToolThatIsOffHasNoInstallationAndNoSetupProblem() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v22.0.0/bin/npm")
        var settings = SettingsValues()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.brewPath = "/nonexistent/bin/brew"
        settings.rubyFolder = "/nonexistent/ruby"
        settings.rustPath = "/nonexistent/bin/rustup"
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"
        settings.disabledBuckets = [.node, .homebrew]

        let toolchain = Toolchain.detect(settings: settings)

        #expect(toolchain.node.isEmpty)
        #expect(toolchain.homebrew == nil)
        #expect(toolchain.setupProblems[.node] == nil)
        #expect(toolchain.setupProblems[.homebrew] == nil)
        #expect(toolchain.setupProblems[.ruby] != nil)
        #expect(toolchain.scanners(runner: CommandRunner()).isEmpty)
    }

    @Test func settingsCanStillSeeAToolThatIsOff() throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try home.makeExecutable("node/v22.0.0/bin/npm")
        var settings = SettingsValues()
        settings.nodeFolder = home.url.appending(path: "node").path
        settings.disabledBuckets = [.node]

        let toolchain = Toolchain.detect(settings: settings, includingDisabledTools: true)

        #expect(toolchain.node.map(\.version) == ["22.0.0"])
    }

    @Test func theStateListsOnlyTheToolsThatAreOn() async {
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let state = AppState(scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine)], runner: machine.runner)
        #expect(state.enabledBuckets == [.homebrew, .node, .ruby, .rust, .python])

        var settings = SettingsValues()
        settings.brewPath = "/nonexistent/bin/brew"
        settings.nodeFolder = "/nonexistent/node"
        settings.rubyFolder = "/nonexistent/ruby"
        settings.rustPath = "/nonexistent/bin/rustup"
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"
        settings.disabledBuckets = [.ruby]
        state.apply(settings)

        #expect(state.enabledBuckets == [.homebrew, .node, .rust, .python])
        #expect(state.disabledBuckets == [.ruby])
        #expect(state.setupProblems[.ruby] == nil)
        #expect(state.setupProblems[.node] != nil)
    }

    @Test func turningATurnedOffToolBackOnShowsItAgain() async {
        let machine = FakeMachine(packages: [])
        let state = AppState(scanners: [:], runner: machine.runner)
        var settings = SettingsValues()
        settings.brewPath = "/nonexistent/bin/brew"
        settings.nodeFolder = "/nonexistent/node"
        settings.rubyFolder = "/nonexistent/ruby"
        settings.rustPath = "/nonexistent/bin/rustup"
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"
        settings.disabledBuckets = [.homebrew]
        state.apply(settings)
        #expect(state.setupProblems[.homebrew] == nil)

        settings.disabledBuckets = []
        state.apply(settings)

        #expect(state.setupProblems[.homebrew] != nil)
        #expect(state.enabledBuckets.contains(.homebrew))
    }

    @Test func theCheckDoesNotScanAToolThatIsOff() async {
        let machine = FakeMachine(packages: [outdatedPackage("git")])
        let state = AppState(scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine)], runner: machine.runner)
        await state.refresh()
        #expect(state.totalOutdated == 1)

        var settings = SettingsValues()
        settings.brewPath = "/nonexistent/bin/brew"
        settings.nodeFolder = "/nonexistent/node"
        settings.rubyFolder = "/nonexistent/ruby"
        settings.rustPath = "/nonexistent/bin/rustup"
        settings.pipxPath = "/nonexistent/bin/pipx"
        settings.uvPath = "/nonexistent/bin/uv"
        settings.disabledBuckets = [.homebrew]
        state.apply(settings)

        #expect(state.totalOutdated == 0)
        #expect(state.readyBuckets.isEmpty)
    }

    @Test func withEveryToolOffThePopoverSaysSo() {
        let machine = FakeMachine(packages: [])
        let state = AppState(scanners: [:], runner: machine.runner)
        var settings = SettingsValues()
        settings.disabledBuckets = [.homebrew, .node, .ruby, .rust, .python]

        state.apply(settings)

        #expect(state.enabledBuckets.isEmpty)
        #expect(state.popoverMode == .noTools)
    }

    @Test func aCheckWithNothingToScanLeavesNoHistoryEntry() async {
        let machine = FakeMachine(packages: [])
        let state = AppState(scanners: [:], runner: machine.runner)

        await state.refresh()

        #expect(state.history.entries.isEmpty)
    }
}

@MainActor
@Suite struct LanguageSettingTests {
    @Test func followsTheMacByDefault() {
        #expect(SettingsValues().language == nil)
    }

    @Test func theChoiceIsSavedAndReadBack() {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)

        store.values.language = "de"
        #expect(SettingsStore(defaults: defaults).values.language == "de")

        store.values.language = nil
        #expect(SettingsStore(defaults: defaults).values.language == nil)
    }

    @Test func aFileWithoutTheFieldFollowsTheMac() {
        let suite = "devhub-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"theme":"dark"}"#.utf8), forKey: "settings.v1")

        #expect(SettingsStore(defaults: defaults).values.language == nil)
    }
}
