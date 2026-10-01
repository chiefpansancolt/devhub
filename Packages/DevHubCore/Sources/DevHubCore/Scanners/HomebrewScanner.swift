public struct HomebrewOptions: Sendable, Equatable {
    /// Runs `brew update` before each scan so the version list is current.
    public var refreshIndexFirst: Bool
    /// Includes casks that update themselves, such as browsers.
    public var includeSelfUpdatingCasks: Bool

    public init(refreshIndexFirst: Bool = true, includeSelfUpdatingCasks: Bool = false) {
        self.refreshIndexFirst = refreshIndexFirst
        self.includeSelfUpdatingCasks = includeSelfUpdatingCasks
    }
}

public struct HomebrewScanner: PackageScanner {
    public let bucket = Bucket.homebrew

    private let installation: HomebrewInstallation
    private let options: HomebrewOptions
    private let support: ScanSupport

    public init(installation: HomebrewInstallation, runner: CommandRunning, options: HomebrewOptions = HomebrewOptions()) {
        self.installation = installation
        self.options = options
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        var issues: [ScanIssue] = []

        if options.refreshIndexFirst, reason == .check {
            let update = command(["update"])
            do {
                try support.requireExit(try await support.run(update), in: update)
            } catch let failure as ScanFailure {
                issues.append(ScanIssue(group: nil, message: failure.message))
            } catch {
                issues.append(ScanIssue(group: nil, message: "\(update.displayText) was cancelled"))
            }
        }

        do {
            let installed = try await readInstalled()
            let outdated = try await readOutdated()
            return ScanResult(packages: BrewParser.merge(installed: installed, outdated: outdated), issues: issues)
        } catch let failure as ScanFailure {
            return ScanResult(packages: [], issues: issues + [ScanIssue(group: nil, message: failure.message)])
        } catch {
            return ScanResult(packages: [], issues: issues + [ScanIssue(group: nil, message: "The scan was cancelled")])
        }
    }

    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == .homebrew else { return nil }
        return command(["upgrade"] + caskFlag(for: package) + [package.name])
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == .homebrew else { return nil }
        return command(["uninstall"] + caskFlag(for: package) + [package.name])
    }

    private func readInstalled() async throws -> [InstalledPackage] {
        let info = command(["info", "--json=v2", "--installed"])
        let result = try await support.run(info)
        try support.requireExit(result, in: info)
        return try support.decode(info, result.standardOutput) { try BrewParser.parseInstalled($0, prefix: installation.prefix) }
    }

    private func readOutdated() async throws -> [BrewParser.OutdatedItem] {
        let outdated = command(["outdated", "--json=v2"] + (options.includeSelfUpdatingCasks ? ["--greedy"] : []))
        let result = try await support.run(outdated)
        try support.requireExit(result, in: outdated)
        return try support.decode(outdated, result.standardOutput, BrewParser.parseOutdated)
    }

    private func caskFlag(for package: InstalledPackage) -> [String] {
        package.kind == .cask ? ["--cask"] : []
    }

    private func command(_ arguments: [String]) -> ToolCommand {
        let searchPath = [installation.prefix.appending(path: "bin"), installation.prefix.appending(path: "sbin")]
        // The scan refreshes the index itself when the option is on. Other commands must not start a hidden update.
        let extra = ["HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"]
        return ToolCommand(
            executable: installation.executable,
            arguments: arguments,
            environment: ToolEnvironment.make(searchPath: searchPath, extra: extra)
        )
    }
}
