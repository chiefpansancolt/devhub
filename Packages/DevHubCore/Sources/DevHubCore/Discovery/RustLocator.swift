import Foundation

public struct RustInstallation: Sendable, Equatable {
    public let rustup: URL
    public let cargo: URL?

    public init(rustup: URL, cargo: URL? = nil) {
        self.rustup = rustup
        self.cargo = cargo
    }

    public var binDirectory: URL {
        rustup.deletingLastPathComponent()
    }
}

public enum RustLocator {
    public static func locate(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> RustInstallation? {
        let candidates = [
            home.appending(path: ".cargo/bin/rustup"),
            URL(filePath: "/opt/homebrew/opt/rustup/bin/rustup"),
            URL(filePath: "/usr/local/opt/rustup/bin/rustup")
        ]
        return candidates
            .first { fileManager.isExecutableFile(atPath: $0.path) }
            .map { installation(rustup: $0, fileManager: fileManager) }
    }

    public static func installation(rustup: URL, fileManager: FileManager = .default) -> RustInstallation {
        let cargo = rustup.deletingLastPathComponent().appending(path: "cargo")
        return RustInstallation(rustup: rustup, cargo: fileManager.isExecutableFile(atPath: cargo.path) ? cargo : nil)
    }
}
