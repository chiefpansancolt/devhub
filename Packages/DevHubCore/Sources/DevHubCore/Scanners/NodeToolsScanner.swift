import Foundation

public struct NodeToolsScanner: PackageScanner {
    public let bucket = Bucket.node

    private let installations: [NodePackageManagerInstallation]
    private let nodeBinDirectory: URL?
    private let home: URL
    private let support: ScanSupport

    public init(
        installations: [NodePackageManagerInstallation],
        runner: CommandRunning,
        nodeBinDirectory: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.installations = installations
        self.nodeBinDirectory = nodeBinDirectory
        self.home = home
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        await withTaskGroup(of: (NodePackageManagerInstallation, Result<[InstalledPackage], ScanFailure>).self) { group in
            for installation in installations {
                group.addTask {
                    do {
                        return (installation, .success(try await scan(installation)))
                    } catch let failure as ScanFailure {
                        return (installation, .failure(failure))
                    } catch {
                        return (installation, .failure(.unreadableOutput(command: installation.manager.rawValue, reason: String(localized: "The scan was cancelled", bundle: .module))))
                    }
                }
            }

            var packages: [InstalledPackage] = []
            var issues: [ScanIssue] = []
            for await (installation, result) in group {
                switch result {
                case let .success(found): packages += found
                case let .failure(failure): issues.append(ScanIssue(group: installation.manager.displayName, message: failure.message))
                }
            }
            return ScanResult(packages: packages.sorted { $0.group == $1.group ? $0.name < $1.name : PackageGroup.precedes($0.group ?? "", $1.group ?? "") }, issues: issues.sorted { $0.id < $1.id })
        }
    }

    // The newest version is installed by name. The update commands of these managers stay inside the range that the package was installed with.
    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        guard let installation = installation(for: package) else { return nil }
        let target = "\(package.name)@\(package.availableUpdate ?? "latest")"
        switch installation.manager {
        case .pnpm, .bun: return command(installation, ["add", "-g", target])
        case .yarn: return command(installation, ["global", "add", target])
        }
    }

    public func installCommand(for package: InstalledPackage) -> ToolCommand? {
        updateCommand(for: package)
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard let installation = installation(for: package) else { return nil }
        switch installation.manager {
        case .pnpm, .bun: return command(installation, ["remove", "-g", package.name])
        case .yarn: return command(installation, ["global", "remove", package.name])
        }
    }

    private func installation(for package: InstalledPackage) -> NodePackageManagerInstallation? {
        guard package.bucket == .node else { return nil }
        return installations.first { $0.manager.displayName == package.group }
    }

    private func scan(_ installation: NodePackageManagerInstallation) async throws -> [InstalledPackage] {
        switch installation.manager {
        case .pnpm: try await scanPnpm(installation)
        case .bun: try await scanBun(installation)
        case .yarn: try await scanYarn(installation)
        }
    }

    private func scanPnpm(_ installation: NodePackageManagerInstallation) async throws -> [InstalledPackage] {
        let list = command(installation, ["list", "-g", "--json", "--depth=0"])
        let listResult = try await support.run(list)
        try support.requireExit(listResult, in: list)
        let installed = try support.decode(list, listResult.standardOutput, NodeToolsParser.parsePnpmInstalled)
        guard !installed.isEmpty else { return [] }

        let outdated = command(installation, ["outdated", "-g", "--format", "json"])
        let outdatedResult = try await support.run(outdated)
        // pnpm outdated exits with 1 when at least one package is outdated.
        try support.requireExit(outdatedResult, in: outdated, allowing: [0, 1])
        let updates = try support.decode(outdated, outdatedResult.standardOutput, NodeToolsParser.parsePnpmOutdated)
        return packages(installed, updates: updates, kind: .pnpmGlobal, installation)
    }

    private func scanYarn(_ installation: NodePackageManagerInstallation) async throws -> [InstalledPackage] {
        let version = command(installation, ["--version"])
        let versionResult = try await support.run(version)
        try support.requireExit(versionResult, in: version)
        // Yarn 2 and newer removed global packages.
        guard versionResult.standardOutput.hasPrefix("1.") else { return [] }

        let list = command(installation, ["global", "list"])
        let listResult = try await support.run(list)
        try support.requireExit(listResult, in: list)
        let installed = NodeToolsParser.parseYarnInstalled(listResult.standardOutput)
        guard !installed.isEmpty else { return [] }

        let folder = command(installation, ["global", "dir"])
        let folderResult = try await support.run(folder)
        try support.requireExit(folderResult, in: folder)
        guard let globalFolder = NodeToolsParser.parseYarnGlobalFolder(folderResult.standardOutput) else {
            throw ScanFailure.unreadableOutput(command: folder.displayText, reason: String(localized: "No folder was printed", bundle: .module))
        }

        // yarn outdated reads the package.json of its folder, so it runs inside the global folder.
        let outdated = command(installation, ["--cwd", globalFolder, "outdated", "--json"])
        let outdatedResult = try await support.run(outdated)
        try support.requireExit(outdatedResult, in: outdated, allowing: [0, 1])
        return packages(installed, updates: NodeToolsParser.parseYarnOutdated(outdatedResult.standardOutput), kind: .yarnGlobal, installation)
    }

    private func scanBun(_ installation: NodePackageManagerInstallation) async throws -> [InstalledPackage] {
        let list = command(installation, ["pm", "ls", "-g"])
        let listResult = try await support.run(list)
        // Bun exits with 1 and no package.json message until the first global package is installed.
        if listResult.exitCode == 1, listResult.standardError.contains("No package.json") { return [] }
        try support.requireExit(listResult, in: list)
        let installed = NodeToolsParser.parseBunInstalled(listResult.standardOutput)
        guard !installed.isEmpty else { return [] }

        let outdated = command(installation, ["outdated", "-g"])
        let outdatedResult = try await support.run(outdated)
        try support.requireExit(outdatedResult, in: outdated)
        return packages(installed, updates: NodeToolsParser.parseBunOutdated(outdatedResult.standardOutput), kind: .bunGlobal, installation)
    }

    private func packages(
        _ installed: [NodeToolsParser.InstalledPackage],
        updates: [String: String],
        kind: PackageKind,
        _ installation: NodePackageManagerInstallation
    ) -> [InstalledPackage] {
        installed.map { package in
            InstalledPackage(
                bucket: .node,
                kind: kind,
                name: package.name,
                group: installation.manager.displayName,
                installedVersion: package.version,
                availableUpdate: updates[package.name],
                homepage: "https://www.npmjs.com/package/\(package.name)"
            )
        }
    }

    // pnpm 12 refuses a global install when its global bin folder is not in PATH, and a GUI app has no PNPM_HOME. The macOS default is used.
    // The scripts of pnpm and Yarn start with `#!/usr/bin/env node`. A Node from a version manager is not in the default PATH, so the newest one is added last.
    private func command(_ installation: NodePackageManagerInstallation, _ arguments: [String]) -> ToolCommand {
        let pnpmHome = home.appending(path: "Library/pnpm")
        let searchPath = [installation.binDirectory]
            + (installation.manager == .pnpm ? [pnpmHome.appending(path: "bin")] : [])
            + (nodeBinDirectory.map { [$0] } ?? [])
        return ToolCommand(
            executable: installation.executable,
            arguments: arguments,
            environment: ToolEnvironment.make(
                searchPath: searchPath,
                extra: ["NO_COLOR": "1", "NO_UPDATE_NOTIFIER": "1", "PNPM_HOME": pnpmHome.path]
            ),
            context: installation.manager.displayName
        )
    }
}
