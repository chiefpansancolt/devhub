import Foundation

public struct NodeOptions: Sendable, Equatable {
    public var includeNpm: Bool

    public init(includeNpm: Bool = true) {
        self.includeNpm = includeNpm
    }
}

public struct NodeScanner: PackageScanner {
    public let bucket = Bucket.node

    private static let concurrentLookups = 6

    private let installations: [NodeInstallation]
    private let options: NodeOptions
    private let support: ScanSupport

    public init(installations: [NodeInstallation], runner: CommandRunning, options: NodeOptions = NodeOptions()) {
        self.installations = installations
        self.options = options
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        await withTaskGroup(of: (NodeInstallation, Result<[InstalledPackage], ScanFailure>).self) { group in
            for installation in installations {
                group.addTask {
                    do {
                        return (installation, .success(try await scan(installation)))
                    } catch let failure as ScanFailure {
                        return (installation, .failure(failure))
                    } catch {
                        return (installation, .failure(.unreadableOutput(command: "npm", reason: String(localized: "The scan was cancelled", bundle: .module))))
                    }
                }
            }

            var packages: [InstalledPackage] = []
            var issues: [ScanIssue] = []
            for await (installation, result) in group {
                switch result {
                case let .success(found): packages += found
                case let .failure(failure): issues.append(ScanIssue(group: installation.version, message: failure.message))
                }
            }
            return ScanResult(packages: Self.sorted(packages), issues: issues.sorted { $0.id < $1.id })
        }
    }

    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        command(for: package, arguments: ["install", "-g", "\(package.name)@\(package.availableUpdate ?? "latest")"])
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        if package.kind.isRuntime { return RuntimeInstaller().uninstallCommand(for: package) }
        return command(for: package, arguments: ["uninstall", "-g", package.name])
    }

    public func installCommand(for package: InstalledPackage) -> ToolCommand? {
        package.kind.isRuntime ? RuntimeInstaller().command(for: package) : updateCommand(for: package)
    }

    private func scan(_ installation: NodeInstallation) async throws -> [InstalledPackage] {
        let list = command(for: installation, arguments: ["ls", "-g", "--depth=0", "--json"])
        let listResult = try await support.run(list)
        // npm ls exits with 1 when it finds problems but still prints the packages.
        try support.requireExit(listResult, in: list, allowing: [0, 1])
        let installed = try support.decode(list, listResult.standardOutput, NpmParser.parseInstalled)

        let outdated = command(for: installation, arguments: ["outdated", "-g", "--json"])
        let outdatedResult = try await support.run(outdated)
        // npm outdated exits with 1 when at least one package is outdated.
        try support.requireExit(outdatedResult, in: outdated, allowing: [0, 1])
        let updates = try support.decode(outdated, outdatedResult.standardOutput, NpmParser.parseOutdated)
        let allowedVersions = await highestAllowedVersions(of: updates, in: installation)

        return installed
            .filter { options.includeNpm || $0.name != "npm" }
            .map { package in
                InstalledPackage(
                    bucket: .node,
                    kind: .npmGlobal,
                    name: package.name,
                    group: installation.version,
                    installedVersion: package.version,
                    availableUpdate: allowedVersions[package.name],
                    homepage: "https://www.npmjs.com/package/\(package.name)",
                    installPath: installation.globalModules.appending(path: package.name).path
                )
            }
    }

    private func highestAllowedVersions(
        of updates: [String: NpmParser.OutdatedPackage],
        in installation: NodeInstallation
    ) async -> [String: String] {
        let lookups = await BoundedConcurrency.map(Array(updates), limit: Self.concurrentLookups) { name, update in
            (name, await highestAllowedVersion(of: name, current: update.current, latest: update.latest, in: installation))
        }
        return lookups.reduce(into: [:]) { versions, lookup in
            if let version = lookup.1 { versions[lookup.0] = version }
        }
    }

    private func highestAllowedVersion(
        of name: String,
        current: String,
        latest: String,
        in installation: NodeInstallation
    ) async -> String? {
        let view = command(for: installation, arguments: ["view", "\(name)@>\(current)", "version", "engines.node", "--json"])
        guard let result = try? await support.run(view), result.exitCode == 0,
              let published = try? NpmParser.parsePublishedVersions(Data(result.standardOutput.utf8)) else {
            return latest
        }

        func isAllowed(_ version: NpmParser.PublishedVersion) -> Bool {
            NodeEngineRange(version.nodeRange).allows(installation.version)
        }

        if published.first(where: { $0.version == latest }).map(isAllowed) ?? true {
            return latest
        }
        let keepsPrereleases = current.contains("-")
        return published
            .filter { isAllowed($0) && (keepsPrereleases || !$0.version.contains("-")) }
            .map { PackageVersion($0.version) }
            .max()?
            .text
    }

    private static let searchBatch = 6
    private static let searchBatches = 8

    /// Finds the version that installing `package` would install. The newest version is checked first. Older versions are only
    /// searched when the newest does not run on this Node version, because one lookup for every version cannot tell the engines apart:
    /// npm prints plain version numbers when some of the versions have no `engines` field.
    public func resolveInstall(of package: InstalledPackage) async -> PackageResolution? {
        guard package.bucket == .node, let installation = installations.first(where: { $0.version == package.group }) else { return nil }
        let latest = command(for: installation, arguments: ["view", package.name, "version", "engines.node", "--json"])
        let result: CommandResult
        switch await support.lookup(latest, tool: "npm") {
        case let .ran(value): result = value
        case let .cannotRun(resolution): return resolution
        }
        guard result.exitCode == 0 else {
            return result.standardError.contains("E404") ? .notFound : .commandFailed("npm", result)
        }
        guard let newest = (try? NpmParser.parsePublishedVersions(Data(result.standardOutput.utf8)))?.first else { return .unreadable("npm", result) }

        func runs(_ version: NpmParser.PublishedVersion) -> Bool {
            NodeEngineRange(version.nodeRange).allows(installation.version)
        }
        if runs(newest) { return .current(version: newest.version) }

        let list: CommandResult
        switch await support.lookup(command(for: installation, arguments: ["view", package.name, "versions", "--json"]), tool: "npm") {
        case let .ran(value): list = value
        case let .cannotRun(resolution): return resolution
        }
        guard list.exitCode == 0 else { return .commandFailed("npm", list) }
        let candidates = VersionSearch.candidates(below: newest.version, among: NpmParser.parseVersionList(Data(list.standardOutput.utf8)))
        var lookupFailed = false
        for batch in candidates.chunked(into: Self.searchBatch).prefix(Self.searchBatches) {
            let checked = await BoundedConcurrency.map(batch, limit: Self.searchBatch) { version -> NpmParser.PublishedVersion? in
                let view = command(for: installation, arguments: ["view", "\(package.name)@\(version)", "version", "engines.node", "--json"])
                guard case let .ran(result) = await support.lookup(view, tool: "npm"), result.exitCode == 0 else { return nil }
                return (try? NpmParser.parsePublishedVersions(Data(result.standardOutput.utf8)))?.first
            }
            lookupFailed = lookupFailed || checked.contains { $0 == nil }
            if let match = checked.compactMap({ $0 }).first(where: runs) { return .older(newest: newest.version, installs: match.version) }
        }
        if lookupFailed {
            return .unavailable(reason: String(localized: "Some older versions could not be checked, so no compatible version was found.", bundle: .module), details: nil)
        }
        return .incompatible(newest: newest.version)
    }

    private func command(for package: InstalledPackage, arguments: [String]) -> ToolCommand? {
        guard package.bucket == .node, let installation = installations.first(where: { $0.version == package.group }) else {
            return nil
        }
        return command(for: installation, arguments: arguments)
    }

    private func command(for installation: NodeInstallation, arguments: [String]) -> ToolCommand {
        ToolCommand(
            executable: installation.npm,
            arguments: arguments,
            environment: ToolEnvironment.make(
                searchPath: [installation.binDirectory],
                extra: ["NO_UPDATE_NOTIFIER": "1", "npm_config_update_notifier": "false"]
            ),
            context: "Node \(installation.version)"
        )
    }

    private static func sorted(_ packages: [InstalledPackage]) -> [InstalledPackage] {
        packages.sorted {
            if $0.group != $1.group { return PackageGroup.precedes($0.group ?? "", $1.group ?? "") }
            return $0.name < $1.name
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
