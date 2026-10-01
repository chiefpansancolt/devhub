import Foundation

public enum RubyVersionManager: String, Sendable, CaseIterable {
    case rvm
    case rbenv
    case chruby
    case asdf
}

public struct RubyInstallation: Sendable, Equatable, Identifiable {
    /// The version without a `ruby-` prefix, for example `3.3.12`.
    public let version: String
    public let manager: RubyVersionManager
    /// The folder that holds `bin`.
    public let root: URL
    /// The folders that hold installed gems. Empty when the Ruby keeps its gems inside its own folder.
    public let gemFolders: [URL]

    public init(version: String, manager: RubyVersionManager, root: URL, gemFolders: [URL] = []) {
        self.version = version
        self.manager = manager
        self.root = root
        self.gemFolders = gemFolders
    }

    public var id: String { "\(manager.rawValue)-\(version)" }
    public var binDirectory: URL { root.appending(path: "bin") }
    public var gem: URL { binDirectory.appending(path: "gem") }

    /// RVM and chruby keep gems outside the Ruby folder, so `gem` needs these variables to find them.
    public var gemEnvironment: [String: String] {
        guard let home = gemFolders.first else { return [:] }
        return ["GEM_HOME": home.path, "GEM_PATH": gemFolders.map(\.path).joined(separator: ":")]
    }
}

public struct RubyVersionDiscovery: Sendable {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Every Ruby version whose `gem` can run, newest first. The macOS system Ruby is left out because its gems need `sudo`.
    public func installations() -> [RubyInstallation] {
        let found = rvm() + rbenv() + chruby() + asdf()
        return found
            .filter { FileManager.default.isExecutableFile(atPath: $0.gem.path) }
            .sorted { PackageVersion($0.version) > PackageVersion($1.version) }
    }

    private func rvm() -> [RubyInstallation] {
        versions(in: ".rvm/rubies", prefix: "ruby-").map { version in
            let gems = home.appending(path: ".rvm/gems/ruby-\(version)")
            return RubyInstallation(
                version: version,
                manager: .rvm,
                root: home.appending(path: ".rvm/rubies/ruby-\(version)"),
                gemFolders: [gems, URL(filePath: gems.path + "@global")]
            )
        }
    }

    private func rbenv() -> [RubyInstallation] {
        versions(in: ".rbenv/versions", prefix: "").map {
            RubyInstallation(version: $0, manager: .rbenv, root: home.appending(path: ".rbenv/versions/\($0)"))
        }
    }

    private func chruby() -> [RubyInstallation] {
        versions(in: ".rubies", prefix: "ruby-").map {
            RubyInstallation(
                version: $0,
                manager: .chruby,
                root: home.appending(path: ".rubies/ruby-\($0)"),
                gemFolders: [home.appending(path: ".gem/ruby/\($0)")]
            )
        }
    }

    private func asdf() -> [RubyInstallation] {
        versions(in: ".asdf/installs/ruby", prefix: "").map {
            RubyInstallation(version: $0, manager: .asdf, root: home.appending(path: ".asdf/installs/ruby/\($0)"))
        }
    }

    private func versions(in folder: String, prefix: String) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: folder).path)) ?? []
        return entries
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .filter { $0.first?.isNumber == true }
    }
}
