import Foundation

/// Builds the commands that install and uninstall a Node or Ruby version through its version manager.
///
/// The subject is an `InstalledPackage` of kind `runtime` or `runtimeAsDefault`, with the tool as the name and
/// the manager as the group. An install reads the version from the available update, and an uninstall reads it from the installed version.
public struct RuntimeInstaller: Sendable {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func command(for package: InstalledPackage) -> ToolCommand? {
        guard package.kind.isRuntime,
              let manager = package.group.flatMap(RuntimeManager.init(rawValue:)),
              let version = package.availableUpdate, RuntimeReleaseParser.isPlainVersion(version),
              let script = script(manager: manager, bucket: package.bucket, version: version, setsDefault: package.kind == .runtimeAsDefault)
        else { return nil }

        return bashCommand(script)
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        guard package.kind.isRuntime,
              let manager = package.group.flatMap(RuntimeManager.init(rawValue:)),
              RuntimeReleaseParser.isPlainVersion(package.installedVersion),
              let script = uninstallScript(manager: manager, bucket: package.bucket, version: package.installedVersion)
        else { return nil }
        return bashCommand(script)
    }

    private func bashCommand(_ script: String) -> ToolCommand {
        let managerFolders = [".volta/bin", ".asdf/bin", ".asdf/shims", ".rbenv/bin", ".rbenv/shims", ".rvm/bin", ".cargo/bin"]
        let environment = ToolEnvironment.make(
            searchPath: managerFolders.map { home.appending(path: $0) },
            extra: ["NVM_DIR": home.appending(path: ".nvm").path],
            home: home
        )
        return ToolCommand(executable: URL(filePath: "/bin/bash"), arguments: ["-c", script], environment: environment)
    }

    // The version is checked by `RuntimeReleaseParser.isPlainVersion`, so it holds only digits and dots and is safe in a script.
    private func uninstallScript(manager: RuntimeManager, bucket: Bucket, version: String) -> String? {
        switch (bucket, manager) {
        // Without --no-use, nvm.sh activates the default version when it loads, and nvm refuses to uninstall the active version.
        // nvm keeps the default alias after it removes the version, so the script removes the alias when it pointed at that version.
        case (.node, .nvm):
            ". \"$NVM_DIR/nvm.sh\" --no-use && was_default=$(nvm version default 2>/dev/null || true) && nvm uninstall \(version) && { [ \"$was_default\" != \"v\(version)\" ] || nvm unalias default; }"
        case (.node, .fnm): "fnm uninstall \(version)"
        case (.node, .asdf): "asdf uninstall nodejs \(version)"
        case (.ruby, .rbenv): "rbenv uninstall -f \(version)"
        case (.ruby, .rvm): ". \"$HOME/.rvm/scripts/rvm\" && rvm uninstall \(version)"
        case (.ruby, .asdf): "asdf uninstall ruby \(version)"
        default: nil
        }
    }

    // The version is checked by `RuntimeReleaseParser.isPlainVersion`, so it holds only digits and dots and is safe in a script.
    private func script(manager: RuntimeManager, bucket: Bucket, version: String, setsDefault: Bool) -> String? {
        switch (bucket, manager) {
        case (.node, .nvm):
            let install = ". \"$NVM_DIR/nvm.sh\" && nvm install \(version)"
            return setsDefault ? "\(install) && nvm alias default \(version)" : install
        case (.node, .fnm):
            return setsDefault ? "fnm install \(version) && fnm default \(version)" : "fnm install \(version)"
        // Volta makes a version the default when it installs it, so a version that must not become the default is only fetched.
        case (.node, .volta):
            return setsDefault ? "volta install node@\(version)" : "volta fetch node@\(version)"
        case (.node, .asdf):
            return asdf("nodejs", version, setsDefault)
        case (.ruby, .rbenv):
            return setsDefault ? "rbenv install \(version) && rbenv global \(version)" : "rbenv install \(version)"
        case (.ruby, .rvm):
            let install = ". \"$HOME/.rvm/scripts/rvm\" && rvm install \(version)"
            return setsDefault ? "\(install) --default" : install
        case (.ruby, .asdf):
            return asdf("ruby", version, setsDefault)
        default:
            return nil
        }
    }

    // asdf 0.16 replaced `asdf global` with `asdf set`, so the script tries the new command first.
    private func asdf(_ plugin: String, _ version: String, _ setsDefault: Bool) -> String {
        let install = "asdf install \(plugin) \(version)"
        return setsDefault ? "\(install) && { asdf set --home \(plugin) \(version) || asdf global \(plugin) \(version); }" : install
    }
}
