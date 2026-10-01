public struct NodeOptions: Sendable, Equatable {
    /// Includes `npm` itself in the list of global packages.
    public var includeNpm: Bool

    public init(includeNpm: Bool = true) {
        self.includeNpm = includeNpm
    }
}

public struct NodeScanner: PackageScanner {
    public let bucket = Bucket.node

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
        command(for: package, arguments: ["install", "-g", "\(package.name)@latest"])
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        command(for: package, arguments: ["uninstall", "-g", package.name])
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

        return installed
            .filter { options.includeNpm || $0.name != "npm" }
            .map { package in
                InstalledPackage(
                    bucket: .node,
                    kind: .npmGlobal,
                    name: package.name,
                    group: installation.version,
                    installedVersion: package.version,
                    availableUpdate: updates[package.name]?.latest,
                    homepage: "https://www.npmjs.com/package/\(package.name)",
                    installPath: installation.globalModules.appending(path: package.name).path
                )
            }
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
            if $0.group != $1.group { return PackageVersion($0.group ?? "") > PackageVersion($1.group ?? "") }
            return $0.name < $1.name
        }
    }
}
