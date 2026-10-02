import Foundation

public enum PathCheck: Sendable, Equatable {
    case found(String)
    case problem(String)

    public var isFound: Bool {
        if case .found = self { true } else { false }
    }
}

public enum PathValidation {
    public static func homebrew(path: String, runner: CommandRunning) async -> PathCheck {
        guard FileManager.default.fileExists(atPath: path) else {
            return .problem(String(localized: "Nothing was found at this path.", bundle: .module))
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .problem(String(localized: "This file is not a program.", bundle: .module))
        }
        let command = ToolCommand(executable: URL(filePath: path), arguments: ["--version"], environment: ToolEnvironment.make())
        guard let result = try? await runner.run(command), result.succeeded else {
            return .problem(String(localized: "This program did not run as brew.", bundle: .module))
        }
        let first = result.standardOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.hasPrefix("Homebrew") ? .found(first) : .problem(String(localized: "This program did not run as brew.", bundle: .module))
    }

    public static func rustup(path: String, runner: CommandRunning) async -> PathCheck {
        guard FileManager.default.fileExists(atPath: path) else {
            return .problem(String(localized: "Nothing was found at this path.", bundle: .module))
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .problem(String(localized: "This file is not a program.", bundle: .module))
        }
        let command = ToolCommand(executable: URL(filePath: path), arguments: ["--version"], environment: ToolEnvironment.make())
        guard let result = try? await runner.run(command), result.succeeded else {
            return .problem(String(localized: "This program did not run as rustup.", bundle: .module))
        }
        let first = result.standardOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.hasPrefix("rustup") ? .found(first) : .problem(String(localized: "This program did not run as rustup.", bundle: .module))
    }

    public static func pythonManager(_ manager: PythonManager, path: String, runner: CommandRunning) async -> PathCheck {
        guard FileManager.default.fileExists(atPath: path) else {
            return .problem(String(localized: "Nothing was found at this path.", bundle: .module))
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .problem(String(localized: "This file is not a program.", bundle: .module))
        }
        let command = ToolCommand(executable: URL(filePath: path), arguments: ["--version"], environment: ToolEnvironment.make())
        let notThisProgram = PathCheck.problem(String(localized: "This program did not run as \(manager.rawValue).", bundle: .module))
        guard let result = try? await runner.run(command), result.succeeded else { return notThisProgram }
        let first = result.standardOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        switch manager {
        case .uv: return first.hasPrefix("uv ") ? .found(first) : notThisProgram
        case .pipx: return first.first?.isNumber == true ? .found("pipx \(first)") : notThisProgram
        }
    }

    public static func nodeManager(_ manager: NodePackageManager, path: String, runner: CommandRunning) async -> PathCheck {
        guard FileManager.default.fileExists(atPath: path) else {
            return .problem(String(localized: "Nothing was found at this path.", bundle: .module))
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .problem(String(localized: "This file is not a program.", bundle: .module))
        }
        let command = ToolCommand(executable: URL(filePath: path), arguments: ["--version"], environment: ToolEnvironment.make())
        guard let result = try? await runner.run(command), result.succeeded,
              let version = result.standardOutput.split(whereSeparator: \.isNewline).first.map(String.init), version.first?.isNumber == true else {
            return .problem(String(localized: "This program did not run as \(manager.displayName).", bundle: .module))
        }
        return .found("\(manager.displayName) \(version)")
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
            return .problem(String(localized: "This folder does not exist.", bundle: .module))
        }
        guard count > 0 else {
            return .problem(String(localized: "No \(noun) versions were found in this folder.", bundle: .module))
        }
        return .found(String(localized: "\(count) versions found", bundle: .module))
    }
}
