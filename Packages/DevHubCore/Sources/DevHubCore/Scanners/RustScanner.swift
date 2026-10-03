import Foundation

public struct RustOptions: Sendable, Equatable {
    public var includeCargoTools: Bool

    public init(includeCargoTools: Bool = true) {
        self.includeCargoTools = includeCargoTools
    }
}

public struct RustScanner: PackageScanner {
    public let bucket = Bucket.rust

    private static let concurrentLookups = 6
    private static let rustupPackageName = "rustup"

    private let installation: RustInstallation
    private let options: RustOptions
    private let support: ScanSupport

    public init(installation: RustInstallation, runner: CommandRunning, options: RustOptions = RustOptions()) {
        self.installation = installation
        self.options = options
        support = ScanSupport(runner: runner)
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        var packages: [InstalledPackage] = []
        var issues: [ScanIssue] = []

        let toolchains = await scanToolchains()
        packages += toolchains.packages
        issues += toolchains.issues

        if options.includeCargoTools, let cargo = installation.cargo {
            do {
                packages += try await scanCargoTools(cargo)
            } catch let failure as ScanFailure {
                issues.append(ScanIssue(group: nil, message: failure.message))
            } catch {
                issues.append(ScanIssue(group: nil, message: String(localized: "The scan was cancelled", bundle: .module)))
            }
        }
        return ScanResult(packages: packages, issues: issues)
    }

    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == .rust else { return nil }
        switch package.kind {
        case .rustToolchain where package.name == Self.rustupPackageName:
            return command(installation.rustup, ["self", "update"])
        case .rustToolchain:
            return command(installation.rustup, ["update", package.name, "--no-self-update"])
        case .cargoTool:
            return installation.cargo.map { command($0, ["install", "--locked", package.name]) }
        default:
            return nil
        }
    }

    public func installCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == .rust else { return nil }
        switch package.kind {
        case .rustToolchain where package.name != Self.rustupPackageName:
            return command(installation.rustup, ["toolchain", "install", package.name, "--no-self-update"])
        case .cargoTool:
            let version = package.availableUpdate.map { ["--version", $0] } ?? []
            return installation.cargo.map { command($0, ["install", "--locked"] + version + [package.name]) }
        default:
            return nil
        }
    }

    public func resolveInstall(of package: InstalledPackage) async -> PackageResolution? {
        guard package.bucket == .rust else { return nil }
        switch package.kind {
        case .rustToolchain where package.name != Self.rustupPackageName:
            return RustupParser.isToolchainName(package.name) ? .current(version: package.name) : .notFound
        case .cargoTool:
            guard let cargo = installation.cargo else {
                return .unavailable(reason: String(localized: "Cargo is not installed.", bundle: .module), details: nil)
            }
            let search = command(cargo, ["search", package.name, "--limit", "10"])
            let result: CommandResult
            switch await support.lookup(search, tool: "cargo") {
            case let .ran(value): result = value
            case let .cannotRun(resolution): return resolution
            }
            guard result.succeeded else { return .commandFailed("cargo", result) }
            return CargoParser.parseLatestVersion(of: package.name, in: result.standardOutput).map { .current(version: $0) } ?? .notFound
        default:
            return nil
        }
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.bucket == .rust else { return nil }
        switch package.kind {
        case .rustToolchain where package.name == Self.rustupPackageName:
            return nil
        case .rustToolchain:
            return command(installation.rustup, ["toolchain", "uninstall", package.name])
        case .cargoTool:
            return installation.cargo.map { command($0, ["uninstall", package.name]) }
        default:
            return nil
        }
    }

    private func scanToolchains() async -> (packages: [InstalledPackage], issues: [ScanIssue]) {
        var issues: [ScanIssue] = []
        let list = command(installation.rustup, ["toolchain", "list", "-v"])
        let installed: [RustupParser.InstalledToolchain]
        do {
            let result = try await support.run(list)
            try support.requireExit(result, in: list)
            installed = RustupParser.parseToolchains(result.standardOutput)
        } catch let failure as ScanFailure {
            return ([], [ScanIssue(group: nil, message: failure.message)])
        } catch {
            return ([], [ScanIssue(group: nil, message: String(localized: "The scan was cancelled", bundle: .module))])
        }

        var statuses: [String: RustupParser.ToolchainStatus] = [:]
        let check = command(installation.rustup, ["check"])
        do {
            // rustup check exits with 100 when at least one update exists.
            let result = try await support.run(check)
            try support.requireExit(result, in: check, allowing: [0, 100])
            statuses = Dictionary(
                RustupParser.parseCheck(result.standardOutput).map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch let failure as ScanFailure {
            issues.append(ScanIssue(group: nil, message: failure.message))
        } catch {
            issues.append(ScanIssue(group: nil, message: String(localized: "The scan was cancelled", bundle: .module)))
        }

        var packages: [InstalledPackage] = []
        for toolchain in installed {
            let version: String?
            if let status = statuses[toolchain.name] {
                version = status.installedVersion
            } else {
                version = await compilerVersion(of: toolchain.name)
            }
            guard let version else { continue }
            packages.append(InstalledPackage(
                bucket: .rust,
                kind: .rustToolchain,
                name: toolchain.name,
                installedVersion: version,
                availableUpdate: statuses[toolchain.name]?.availableVersion,
                homepage: "https://www.rust-lang.org",
                installPath: toolchain.path
            ))
        }
        if let rustup = statuses[Self.rustupPackageName] {
            packages.append(InstalledPackage(
                bucket: .rust,
                kind: .rustToolchain,
                name: Self.rustupPackageName,
                installedVersion: rustup.installedVersion,
                availableUpdate: rustup.availableVersion,
                homepage: "https://rustup.rs"
            ))
        }
        return (packages, issues)
    }

    private func compilerVersion(of toolchain: String) async -> String? {
        let version = command(installation.rustup, ["run", toolchain, "rustc", "--version"])
        guard let result = try? await support.run(version), result.succeeded else { return nil }
        return RustupParser.parseCompilerVersion(result.standardOutput)
    }

    private func scanCargoTools(_ cargo: URL) async throws -> [InstalledPackage] {
        let list = command(cargo, ["install", "--list"])
        let result = try await support.run(list)
        try support.requireExit(result, in: list)
        let tools = CargoParser.parseInstalled(result.standardOutput)

        let latest = await BoundedConcurrency.map(tools, limit: Self.concurrentLookups) { tool -> String? in
            guard tool.isFromRegistry else { return nil }
            return await latestVersion(of: tool.name, cargo: cargo)
        }
        return zip(tools, latest)
            .map { tool, latest in
                InstalledPackage(
                    bucket: .rust,
                    kind: .cargoTool,
                    name: tool.name,
                    installedVersion: tool.version,
                    availableUpdate: latest,
                    homepage: tool.isFromRegistry ? "https://crates.io/crates/\(tool.name)" : nil
                )
            }
            .sorted { $0.name < $1.name }
    }

    private func latestVersion(of name: String, cargo: URL) async -> String? {
        let search = command(cargo, ["search", name, "--limit", "10"])
        guard let result = try? await support.run(search), result.succeeded else { return nil }
        return CargoParser.parseLatestVersion(of: name, in: result.standardOutput)
    }

    private func command(_ executable: URL, _ arguments: [String]) -> ToolCommand {
        ToolCommand(
            executable: executable,
            arguments: arguments,
            environment: ToolEnvironment.make(
                searchPath: [installation.binDirectory],
                extra: ["CARGO_TERM_COLOR": "never", "RUSTUP_TERM_COLOR": "never", "NO_COLOR": "1"]
            )
        )
    }
}
