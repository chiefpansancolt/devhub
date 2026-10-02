import Foundation

public enum ScanReason: Sendable {
    case check
    case afterUpdate
}

public protocol PackageScanner: Sendable {
    var bucket: Bucket { get }

    func scan(_ reason: ScanReason) async -> ScanResult

    func updateCommand(for package: InstalledPackage) -> ToolCommand?

    func uninstallCommand(for package: InstalledPackage) -> ToolCommand?
}

extension PackageScanner {
    public func scan() async -> ScanResult {
        await scan(.check)
    }
}

struct ScanSupport {
    let runner: CommandRunning

    func run(_ command: ToolCommand) async throws -> CommandResult {
        do {
            return try await runner.run(command)
        } catch let error as CommandError {
            switch error {
            case let .launchFailed(executable, reason):
                throw ScanFailure.commandFailed(command: command.displayText, exitCode: -1, detail: "could not start \(executable): \(reason)")
            }
        }
    }

    func requireExit(_ result: CommandResult, in command: ToolCommand, allowing allowed: Set<Int32> = [0]) throws {
        guard allowed.contains(result.exitCode) else {
            throw ScanFailure.commandFailed(
                command: command.displayText,
                exitCode: result.exitCode,
                detail: firstLine(of: result.standardError)
            )
        }
    }

    func decode<Value>(_ command: ToolCommand, _ output: String, _ parse: (Data) throws -> Value) throws -> Value {
        do {
            return try parse(Data(output.utf8))
        } catch {
            throw ScanFailure.unreadableOutput(command: command.displayText, reason: String(describing: error))
        }
    }

    private func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}
