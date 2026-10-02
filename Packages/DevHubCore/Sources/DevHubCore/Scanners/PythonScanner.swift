import Foundation

public struct PythonScanner: PackageScanner {
    public let bucket = Bucket.python

    private static let concurrentLookups = 6

    private let installations: [PythonInstallation]
    private let support: ScanSupport

    public init(installations: [PythonInstallation], runner: CommandRunning) {
        self.installations = installations
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        await withTaskGroup(of: (PythonInstallation, Result<[InstalledPackage], ScanFailure>).self) { group in
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
                case let .failure(failure): issues.append(ScanIssue(group: installation.manager.rawValue, message: failure.message))
                }
            }
            return ScanResult(packages: Self.sorted(packages), issues: issues.sorted { $0.id < $1.id })
        }
    }

    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        guard let installation = installation(for: package) else { return nil }
        switch installation.manager {
        case .pipx: return command(installation, ["upgrade", package.name])
        case .uv: return command(installation, ["tool", "upgrade", package.name])
        }
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard let installation = installation(for: package) else { return nil }
        switch installation.manager {
        case .pipx: return command(installation, ["uninstall", package.name])
        case .uv: return command(installation, ["tool", "uninstall", package.name])
        }
    }

    private func installation(for package: InstalledPackage) -> PythonInstallation? {
        guard package.bucket == .python else { return nil }
        return installations.first { $0.manager.rawValue == package.group }
    }

    private func scan(_ installation: PythonInstallation) async throws -> [InstalledPackage] {
        switch installation.manager {
        case .pipx: try await scanPipx(installation)
        case .uv: try await scanUv(installation)
        }
    }

    private func scanPipx(_ installation: PythonInstallation) async throws -> [InstalledPackage] {
        let list = command(installation, ["list", "--json"])
        let result = try await support.run(list)
        try support.requireExit(result, in: list)
        let tools = try support.decode(list, result.standardOutput, PythonParser.parsePipxList)

        let latest = await BoundedConcurrency.map(tools, limit: Self.concurrentLookups) { tool in
            await latestVersion(of: tool.name, installation)
        }
        return zip(tools, latest).map { tool, latest in
            package(tool, latest: latest, installation)
        }
    }

    private func scanUv(_ installation: PythonInstallation) async throws -> [InstalledPackage] {
        let list = command(installation, ["tool", "list"])
        let result = try await support.run(list)
        try support.requireExit(result, in: list)
        let tools = PythonParser.parseUvList(result.standardOutput)

        // uv before 0.8 has no --outdated flag. Its tools are listed without update checks.
        let outdated = command(installation, ["tool", "list", "--outdated", "--show-version-specifiers"])
        var updates: [String: String] = [:]
        if let outdatedResult = try? await support.run(outdated), outdatedResult.succeeded {
            for entry in PythonParser.parseUvList(outdatedResult.standardOutput) where entry.latestIsReachable {
                updates[entry.tool.name] = entry.latest
            }
        }
        return tools.map { package($0.tool, latest: updates[$0.tool.name], installation) }
    }

    private func latestVersion(of tool: String, _ installation: PythonInstallation) async -> String? {
        let outdated = command(installation, ["runpip", tool, "list", "--outdated", "--format=json"])
        guard let result = try? await support.run(outdated), result.succeeded else { return nil }
        return PythonParser.parseLatestVersion(of: tool, in: Data(result.standardOutput.utf8))
    }

    private func package(_ tool: PythonParser.InstalledTool, latest: String?, _ installation: PythonInstallation) -> InstalledPackage {
        InstalledPackage(
            bucket: .python,
            kind: .pythonTool,
            name: tool.name,
            group: installation.manager.rawValue,
            installedVersion: tool.version,
            availableUpdate: latest,
            homepage: "https://pypi.org/project/\(tool.name)/"
        )
    }

    private func command(_ installation: PythonInstallation, _ arguments: [String]) -> ToolCommand {
        ToolCommand(
            executable: installation.executable,
            arguments: arguments,
            environment: ToolEnvironment.make(searchPath: [installation.binDirectory], extra: ["NO_COLOR": "1"]),
            context: installation.manager.rawValue
        )
    }

    private static func sorted(_ packages: [InstalledPackage]) -> [InstalledPackage] {
        packages.sorted {
            if $0.group != $1.group { return PackageGroup.precedes($0.group ?? "", $1.group ?? "") }
            return $0.name < $1.name
        }
    }
}
