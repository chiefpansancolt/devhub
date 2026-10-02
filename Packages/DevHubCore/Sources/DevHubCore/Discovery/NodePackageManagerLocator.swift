import Foundation

public enum NodePackageManager: String, Sendable, CaseIterable, Identifiable {
    case pnpm
    case bun
    case yarn

    public var id: String { rawValue }

    /// The name the sidebar shows. It is also the group of every package of this manager.
    public var displayName: String {
        switch self {
        case .pnpm: "pnpm"
        case .bun: "Bun"
        case .yarn: "Yarn"
        }
    }
}

public struct NodePackageManagerInstallation: Sendable, Equatable, Identifiable {
    public let manager: NodePackageManager
    public let executable: URL

    public init(manager: NodePackageManager, executable: URL) {
        self.manager = manager
        self.executable = executable
    }

    public var id: String { manager.rawValue }

    public var binDirectory: URL {
        executable.deletingLastPathComponent()
    }
}

public enum NodePackageManagerLocator {
    /// A manager installed with `npm install -g` lives in the `bin` folder of one Node version, so the newest versions are searched too.
    public static func locate(
        nodeInstallations: [NodeInstallation] = [],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [NodePackageManagerInstallation] {
        NodePackageManager.allCases.compactMap { manager in
            candidates(for: manager, nodeInstallations: nodeInstallations, home: home)
                .first { fileManager.isExecutableFile(atPath: $0.path) }
                .map { NodePackageManagerInstallation(manager: manager, executable: $0) }
        }
    }

    private static func candidates(for manager: NodePackageManager, nodeInstallations: [NodeInstallation], home: URL) -> [URL] {
        let name = manager.rawValue
        let own: [URL]
        switch manager {
        case .pnpm: own = [home.appending(path: "Library/pnpm"), home.appending(path: ".local/share/pnpm")]
        case .bun: own = [home.appending(path: ".bun/bin")]
        case .yarn: own = [home.appending(path: ".yarn/bin")]
        }
        let shared = [URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/local/bin")]
        let insideNode = nodeInstallations
            .sorted { PackageVersion($0.version) > PackageVersion($1.version) }
            .map(\.binDirectory)
        return (own + shared + insideNode).map { $0.appending(path: name) }
    }
}
