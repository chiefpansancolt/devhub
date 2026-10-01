import Foundation

public enum PathCheck: Sendable, Equatable {
    /// The path works. The text says what was found.
    case found(String)
    /// The path does not work. The text says why.
    case problem(String)

    public var isFound: Bool {
        if case .found = self { true } else { false }
    }
}

public enum PathValidation {
    /// Runs `brew --version` to be sure the file is Homebrew.
    public static func homebrew(path: String, runner: CommandRunning) async -> PathCheck {
        guard FileManager.default.fileExists(atPath: path) else {
            return .problem("Nothing was found at this path.")
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .problem("This file is not a program.")
        }
        let command = ToolCommand(executable: URL(filePath: path), arguments: ["--version"], environment: ToolEnvironment.make())
        guard let result = try? await runner.run(command), result.succeeded else {
            return .problem("This program did not run as brew.")
        }
        let first = result.standardOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.hasPrefix("Homebrew") ? .found(first) : .problem("This program did not run as brew.")
    }

    public static func nodeFolder(path: String) -> PathCheck {
        folder(path: path, count: NodeVersionDiscovery(versionsFolder: URL(filePath: path)).installations().count, noun: "Node")
    }

    public static func rubyFolder(path: String) -> PathCheck {
        folder(path: path, count: RubyVersionDiscovery(versionsFolder: URL(filePath: path)).installations().count, noun: "Ruby")
    }

    private static func folder(path: String, count: Int, noun: String) -> PathCheck {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
            return .problem("This folder does not exist.")
        }
        guard count > 0 else {
            return .problem("No \(noun) versions were found in this folder.")
        }
        return .found(count == 1 ? "1 version found" : "\(count) versions found")
    }
}
