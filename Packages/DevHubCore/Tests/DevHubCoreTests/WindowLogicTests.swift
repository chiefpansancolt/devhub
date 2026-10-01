import Foundation
import Testing
@testable import DevHubCore

@Suite struct PackageScopeTests {
    private let git = InstalledPackage(bucket: .homebrew, kind: .formula, name: "git", installedVersion: "2.47.0")
    private let raycast = InstalledPackage(bucket: .homebrew, kind: .cask, name: "raycast", installedVersion: "1.0")
    private let typescript = InstalledPackage(bucket: .node, kind: .npmGlobal, name: "typescript", group: "22.0.0", installedVersion: "5.0")

    @Test func aWholeBucketScopeContainsEveryPackageOfThatBucketOnly() {
        let scope = PackageScope(bucket: .homebrew)

        #expect(scope.contains(git))
        #expect(scope.contains(raycast))
        #expect(!scope.contains(typescript))
    }

    @Test func homebrewScopesFilterByFormulaOrCask() {
        #expect(PackageScope(bucket: .homebrew, group: "formula").contains(git))
        #expect(!PackageScope(bucket: .homebrew, group: "formula").contains(raycast))
        #expect(PackageScope(bucket: .homebrew, group: "cask").contains(raycast))
    }

    @Test func nodeScopesFilterByVersion() {
        #expect(PackageScope(bucket: .node, group: "22.0.0").contains(typescript))
        #expect(!PackageScope(bucket: .node, group: "20.0.0").contains(typescript))
    }

    @Test func listsTheSidebarRowsUnderEachBucket() {
        #expect(PackageScope.groups(of: .homebrew, versions: []).map(\.group) == ["formula", "cask"])
        #expect(PackageScope.groups(of: .node, versions: ["22.0.0", "20.0.0"]).map(\.group) == ["22.0.0", "20.0.0"])
    }
}

@Suite struct PackageListingTests {
    private let packages = [
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "zeta", group: "20.0.0", installedVersion: "1", availableUpdate: "2"),
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "alpha", group: "20.0.0", installedVersion: "1"),
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "beta", group: "22.0.0", installedVersion: "1"),
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "gamma", group: "22.0.0", installedVersion: "1", availableUpdate: "3")
    ]

    @Test func theUpdatesListHasOnlyOutdatedPackagesInScanOrder() {
        let rows = PackageListing.rows(from: packages, mode: .updates, search: "ignored")

        #expect(rows.map(\.name) == ["zeta", "gamma"])
    }

    @Test func theFullListPutsOutdatedFirstThenNewestVersionThenName() {
        let rows = PackageListing.rows(from: packages, mode: .allInstalled, search: "")

        #expect(rows.map(\.name) == ["gamma", "zeta", "beta", "alpha"])
    }

    @Test func searchMatchesNamesWithoutCaringAboutCase() {
        let rows = PackageListing.rows(from: packages, mode: .allInstalled, search: " AL ")

        #expect(rows.map(\.name) == ["alpha"])
    }
}

@MainActor
@Suite struct WindowStateTests {
    private func state(_ machine: FakeMachine, versions: [Bucket: [String]] = [:], runner: CommandRunning? = nil) -> AppState {
        AppState(
            scanners: [.homebrew: FakeScanner(bucket: .homebrew, machine: machine), .node: FakeScanner(bucket: .node, machine: machine)],
            versions: versions,
            runner: runner ?? machine.runner
        )
    }

    private let packages = [
        outdatedPackage("git"),
        outdatedPackage("typescript", bucket: .node, group: "22.0.0"),
        InstalledPackage(bucket: .node, kind: .npmGlobal, name: "pnpm", group: "20.0.0", installedVersion: "9.0")
    ]

    @Test func countsPackagesPerScope() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        #expect(state.packages(in: PackageScope(bucket: .node)).count == 2)
        #expect(state.outdated(in: PackageScope(bucket: .node)).count == 1)
        #expect(state.outdated(in: PackageScope(bucket: .node, group: "20.0.0")).isEmpty)
    }

    @Test func listsEveryNodeVersionEvenOneWithNoPackages() async {
        let state = state(FakeMachine(packages: packages), versions: [.node: ["25.0.0", "22.0.0", "20.0.0"]])
        await state.refresh()

        #expect(state.groupScopes(of: .node).map(\.group) == ["25.0.0", "22.0.0", "20.0.0"])
    }

    @Test func addsAVersionThatHasPackagesButWasNotListed() async {
        let state = state(FakeMachine(packages: packages), versions: [.node: ["22.0.0"]])
        await state.refresh()

        #expect(state.groupScopes(of: .node).map(\.group) == ["22.0.0", "20.0.0"])
    }

    @Test func findsAPackageByItsID() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        #expect(state.package(withID: packages[1].id)?.name == "typescript")
        #expect(state.package(withID: "nope") == nil)
    }

    @Test func showsTheCommandsBeforeTheyRun() async {
        let state = state(FakeMachine(packages: packages))

        #expect(state.updateCommandText(for: packages[0]) == "true update git")
        #expect(state.uninstallCommandText(for: packages[0]) == "true uninstall git")
    }

    @Test func uninstallRemovesThePackageAndScansAgain() async {
        let machine = FakeMachine(packages: packages)
        let state = state(machine)
        await state.refresh()

        await state.uninstall(packages[0])

        #expect(state.package(withID: packages[0].id) == nil)
        #expect(state.uninstallProgress == nil)
        #expect(state.lastOutcomes.map(\.action) == [.uninstall])
        #expect(machine.scanReasons.contains(.afterUpdate))
    }

    @Test func aFailedUninstallStaysUntilDismissed() async {
        let machine = FakeMachine(packages: packages, failing: ["git"])
        let state = state(machine)
        await state.refresh()

        await state.uninstall(packages[0])

        #expect(state.package(withID: packages[0].id) != nil)
        #expect(state.uninstallProgress == UninstallProgress(packageID: packages[0].id, status: .failed("Error: Refusing to uninstall git")))

        state.dismissUninstallFailure()
        #expect(state.uninstallProgress == nil)
    }

    @Test func writesTheCommandAndItsOutputToTheLog() async {
        let state = state(FakeMachine(packages: packages))
        await state.refresh()

        await state.update([packages[0]])

        #expect(state.log.map(\.entry) == [
            LogEntry(kind: .command, text: "$ true update git"),
            LogEntry(kind: .output, text: "updated git")
        ])
        #expect(Set(state.log.map(\.id)).count == state.log.count)
    }

    @Test func marksErrorLinesInTheLog() async {
        let state = state(FakeMachine(packages: packages, failing: ["git"]))
        await state.refresh()

        await state.update([packages[0]])

        #expect(state.log.last?.entry.kind == .error)
    }

    @Test func isBusyWhileAnUpdateRuns() async {
        let state = state(FakeMachine(packages: packages), runner: HangingRunner())
        await state.refresh()

        let task = Task { await state.updateAll() }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(state.isBusy)

        task.cancel()
        await task.value
        #expect(!state.isBusy)
    }

    @Test func refusesAnUninstallWhileBusy() async {
        let machine = FakeMachine(packages: packages)
        let state = state(machine, runner: HangingRunner())
        await state.refresh()

        let task = Task { await state.updateAll() }
        try? await Task.sleep(for: .milliseconds(100))
        await state.uninstall(packages[0])

        #expect(state.uninstallProgress == nil)
        task.cancel()
        await task.value
    }
}

@Suite struct DiskSizeTests {
    @Test func addsUpTheFilesInAFolder() async throws {
        let home = try TemporaryHome()
        defer { home.remove() }
        try Data(repeating: 1, count: 100_000).write(to: home.url.appending(path: "a.bin"))
        try FileManager.default.createDirectory(at: home.url.appending(path: "sub"), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 50_000).write(to: home.url.appending(path: "sub/b.bin"))

        let size = await DiskSize.measure(path: home.url.path)

        #expect((size ?? 0) >= 150_000)
        #expect((size ?? 0) < 400_000)
    }

    @Test func returnsNilForAMissingPath() async {
        #expect(await DiskSize.measure(path: "/nonexistent/folder") == nil)
    }
}
