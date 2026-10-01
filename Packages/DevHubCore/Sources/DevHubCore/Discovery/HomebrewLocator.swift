import Foundation

public struct HomebrewInstallation: Sendable, Equatable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel.
    public var prefix: URL {
        executable.deletingLastPathComponent().deletingLastPathComponent()
    }
}

public enum HomebrewLocator {
    private static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    public static func locate(fileManager: FileManager = .default) -> HomebrewInstallation? {
        candidates
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { HomebrewInstallation(executable: URL(filePath: $0)) }
    }
}
