import Foundation

public enum PythonManager: String, Sendable, CaseIterable, Identifiable {
    case pipx
    case uv

    public var id: String { rawValue }
}

public struct PythonInstallation: Sendable, Equatable, Identifiable {
    public let manager: PythonManager
    public let executable: URL

    public init(manager: PythonManager, executable: URL) {
        self.manager = manager
        self.executable = executable
    }

    public var id: String { manager.rawValue }

    public var binDirectory: URL {
        executable.deletingLastPathComponent()
    }
}

public enum PythonLocator {
    public static func locate(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemFolders: [URL] = [URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/local/bin")],
        fileManager: FileManager = .default
    ) -> [PythonInstallation] {
        PythonManager.allCases.compactMap { manager in
            candidates(for: manager, home: home, systemFolders: systemFolders)
                .first { fileManager.isExecutableFile(atPath: $0.path) }
                .map { PythonInstallation(manager: manager, executable: $0) }
        }
    }

    private static func candidates(for manager: PythonManager, home: URL, systemFolders: [URL]) -> [URL] {
        let name = manager.rawValue
        let folders = [home.appending(path: ".local/bin")] + systemFolders + (manager == .uv ? [home.appending(path: ".cargo/bin")] : [])
        return folders.map { $0.appending(path: name) }
    }
}
