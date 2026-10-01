import Foundation

public enum NodeVersionManager: String, Sendable, CaseIterable {
    case nvm
    case fnm
    case volta
    case asdf
    /// A folder the person chose that DevHub does not recognise as one of the above.
    case custom
}

public struct NodeInstallation: Sendable, Equatable, Identifiable {
    /// The version without a leading `v`, for example `24.21.0`.
    public let version: String
    public let manager: NodeVersionManager
    /// The folder that holds `bin` and `lib/node_modules`.
    public let root: URL

    public init(version: String, manager: NodeVersionManager, root: URL) {
        self.version = version
        self.manager = manager
        self.root = root
    }

    public var id: String { "\(manager.rawValue)-\(version)" }
    public var binDirectory: URL { root.appending(path: "bin") }
    public var npm: URL { binDirectory.appending(path: "npm") }
    public var globalModules: URL { root.appending(path: "lib/node_modules") }
}

public struct NodeVersionDiscovery: Sendable {
    private struct Location {
        let manager: NodeVersionManager
        let folder: String
        /// The path from a version folder to the folder that holds `bin`.
        let rootInsideVersion: String
    }

    private static let locations = [
        Location(manager: .nvm, folder: ".nvm/versions/node", rootInsideVersion: ""),
        Location(manager: .fnm, folder: "Library/Application Support/fnm/node-versions", rootInsideVersion: "installation"),
        Location(manager: .fnm, folder: ".local/share/fnm/node-versions", rootInsideVersion: "installation"),
        Location(manager: .fnm, folder: ".fnm/node-versions", rootInsideVersion: "installation"),
        Location(manager: .volta, folder: ".volta/tools/image/node", rootInsideVersion: ""),
        Location(manager: .asdf, folder: ".asdf/installs/nodejs", rootInsideVersion: "")
    ]

    private let home: URL
    private let versionsFolder: URL?

    /// With a `versionsFolder`, only that folder is searched. It holds one folder per Node version.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, versionsFolder: URL? = nil) {
        self.home = home
        self.versionsFolder = versionsFolder
    }

    /// Every Node version whose `npm` can run, newest first.
    public func installations() -> [NodeInstallation] {
        let fileManager = FileManager.default
        if let versionsFolder {
            return chosenFolderInstallations(in: versionsFolder)
        }
        var found: [NodeInstallation] = []

        for location in Self.locations {
            let folder = home.appending(path: location.folder)
            let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            for entry in entries {
                let version = entry.hasPrefix("v") ? String(entry.dropFirst()) : entry
                guard version.first?.isNumber == true else { continue }
                var root = folder.appending(path: entry)
                if !location.rootInsideVersion.isEmpty {
                    root = root.appending(path: location.rootInsideVersion)
                }
                let installation = NodeInstallation(version: version, manager: location.manager, root: root)
                if fileManager.isExecutableFile(atPath: installation.npm.path) {
                    found.append(installation)
                }
            }
        }

        return found.sorted { PackageVersion($0.version) > PackageVersion($1.version) }
    }

    private func chosenFolderInstallations(in folder: URL) -> [NodeInstallation] {
        let fileManager = FileManager.default
        let manager = Self.manager(for: folder.path)
        let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []

        let found = entries.compactMap { entry -> NodeInstallation? in
            let version = entry.hasPrefix("v") ? String(entry.dropFirst()) : entry
            guard version.first?.isNumber == true else { return nil }
            // fnm keeps the files one folder deeper than the other managers.
            let candidates = [folder.appending(path: entry), folder.appending(path: entry).appending(path: "installation")]
            return candidates
                .map { NodeInstallation(version: version, manager: manager, root: $0) }
                .first { fileManager.isExecutableFile(atPath: $0.npm.path) }
        }
        return found.sorted { PackageVersion($0.version) > PackageVersion($1.version) }
    }

    private static func manager(for path: String) -> NodeVersionManager {
        if path.contains("/.nvm/") { return .nvm }
        if path.contains("fnm") { return .fnm }
        if path.contains("/.volta/") { return .volta }
        if path.contains("/.asdf/") { return .asdf }
        return .custom
    }
}
