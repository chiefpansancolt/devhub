import Foundation

public enum ScanReason: Sendable {
    /// A routine check. Homebrew refreshes its package index first when that option is on.
    case check
    /// A scan right after an update. The index is already current, so Homebrew skips the refresh.
    case afterUpdate
}

public protocol PackageScanner: Sendable {
    var bucket: Bucket { get }

    /// Lists every installed package with its available update. A failure in one part is reported as an issue,
    /// so the packages that could be read are still returned.
    func scan(_ reason: ScanReason) async -> ScanResult

    /// The command that updates one package. `nil` when the package does not belong to this scanner.
    func updateCommand(for package: InstalledPackage) -> ToolCommand?

    /// The command that removes one package. `nil` when the package does not belong to this scanner.
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
