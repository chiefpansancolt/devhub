public struct RubyOptions: Sendable, Equatable {
    public var installDocumentation: Bool

    public init(installDocumentation: Bool = false) {
        self.installDocumentation = installDocumentation
    }
}

public struct RubyScanner: PackageScanner {
    public let bucket = Bucket.ruby

    private let installations: [RubyInstallation]
    private let options: RubyOptions
    private let support: ScanSupport

    public init(installations: [RubyInstallation], runner: CommandRunning, options: RubyOptions = RubyOptions()) {
        self.installations = installations
        self.options = options
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        await withTaskGroup(of: (RubyInstallation, Result<[InstalledPackage], ScanFailure>).self) { group in
            for installation in installations {
                group.addTask {
                    do {
                        return (installation, .success(try await scan(installation)))
                    } catch let failure as ScanFailure {
                        return (installation, .failure(failure))
                    } catch {
                        return (installation, .failure(.unreadableOutput(command: "gem", reason: String(localized: "The scan was cancelled", bundle: .module))))
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
        command(for: package, arguments: ["update", package.name] + (options.installDocumentation ? [] : ["--no-document"]))
    }

    public func installCommand(for package: InstalledPackage) -> ToolCommand? {
        let version = package.availableUpdate.map { ["--version", $0] } ?? []
        return command(for: package, arguments: ["install", package.name] + version + (options.installDocumentation ? [] : ["--no-document"]))
    }

    public func resolveInstall(of package: InstalledPackage) async -> PackageResolution? {
        guard package.bucket == .ruby, let installation = installations.first(where: { $0.version == package.group }) else { return nil }
        let list = command(for: installation, arguments: ["list", "--remote", "--exact", package.name])
        let result: CommandResult
        switch await support.lookup(list, tool: "gem") {
        case let .ran(value): result = value
        case let .cannotRun(resolution): return resolution
        }
        guard result.succeeded else { return .commandFailed("gem", result) }
        return GemParser.parseRemoteVersion(of: package.name, in: result.standardOutput).map { .current(version: $0) } ?? .notFound
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        command(for: package, arguments: ["uninstall", package.name, "--all", "--executables"])
    }

    private func scan(_ installation: RubyInstallation) async throws -> [InstalledPackage] {
        // The output of `gem` on standard error is not read. Broken gem extensions print warnings there on a normal run.
        let list = command(for: installation, arguments: ["list", "--local"])
        let listResult = try await support.run(list)
        try support.requireExit(listResult, in: list)
        let installed = GemParser.parseList(listResult.standardOutput)

        let outdated = command(for: installation, arguments: ["outdated"])
        let outdatedResult = try await support.run(outdated)
        try support.requireExit(outdatedResult, in: outdated)
        let updates = Dictionary(
            GemParser.parseOutdated(outdatedResult.standardOutput).map { ($0.name, $0.latest) },
            uniquingKeysWith: { first, _ in first }
        )

        return installed.compactMap { entry in
            guard let version = entry.displayVersion else { return nil }
            return InstalledPackage(
                bucket: .ruby,
                kind: .gem,
                name: entry.name,
                group: installation.version,
                installedVersion: version,
                availableUpdate: updates[entry.name],
                homepage: "https://rubygems.org/gems/\(entry.name)"
            )
        }
    }

    private func command(for package: InstalledPackage, arguments: [String]) -> ToolCommand? {
        guard package.bucket == .ruby, let installation = installations.first(where: { $0.version == package.group }) else {
            return nil
        }
        return command(for: installation, arguments: arguments)
    }

    // The `gem` script starts with `#!/usr/bin/env ruby`. Its own Ruby must come first in PATH or the macOS system Ruby runs it.
    private func command(for installation: RubyInstallation, arguments: [String]) -> ToolCommand {
        ToolCommand(
            executable: installation.gem,
            arguments: arguments,
            environment: ToolEnvironment.make(searchPath: [installation.binDirectory], extra: installation.gemEnvironment),
            context: "Ruby \(installation.version)"
        )
    }

    private static func sorted(_ packages: [InstalledPackage]) -> [InstalledPackage] {
        packages.sorted {
            if $0.group != $1.group { return PackageGroup.precedes($0.group ?? "", $1.group ?? "") }
            return $0.name < $1.name
        }
    }
}
