import Foundation

public enum OutputSource: Sendable {
    case standardOutput
    case standardError
}

public struct OutputLine: Sendable, Equatable {
    public let source: OutputSource
    public let text: String

    public init(source: OutputSource, text: String) {
        self.source = source
        self.text = text
    }
}

public enum CommandEvent: Sendable, Equatable {
    case output(OutputLine)
    case finished(exitCode: Int32, duration: Duration)
}

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let duration: Duration

    public init(exitCode: Int32, standardOutput: String, standardError: String, duration: Duration = .zero) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum CommandError: Error, Sendable, Equatable {
    case launchFailed(executable: String, reason: String)
}

public protocol CommandRunning: Sendable {
    /// Runs the command to the end. A non-zero exit code is a result, not an error.
    /// Throws `CommandError.launchFailed` when the process cannot start, and `CancellationError` when the task is cancelled.
    func run(_ command: ToolCommand) async throws -> CommandResult

    /// Yields each output line as it arrives, then one `.finished` event. Cancelling the consumer stops the process.
    func stream(_ command: ToolCommand) -> AsyncThrowingStream<CommandEvent, Error>
}

public struct CommandRunner: CommandRunning {
    public init() {}

    public func run(_ command: ToolCommand) async throws -> CommandResult {
        var standardOutput: [String] = []
        var standardError: [String] = []
        var exitCode: Int32 = 0
        var duration = Duration.zero

        for try await event in stream(command) {
            switch event {
            case let .output(line):
                switch line.source {
                case .standardOutput: standardOutput.append(line.text)
                case .standardError: standardError.append(line.text)
                }
            case let .finished(code, elapsed):
                exitCode = code
                duration = elapsed
            }
        }
        try Task.checkCancellation()

        return CommandResult(
            exitCode: exitCode,
            standardOutput: standardOutput.joined(separator: "\n"),
            standardError: standardError.joined(separator: "\n"),
            duration: duration
        )
    }

    public func stream(_ command: ToolCommand) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = command.executable
            process.arguments = command.arguments
            process.environment = command.environment
            process.standardInput = FileHandle.nullDevice

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let drained = DispatchGroup()
            let outputReader = LineReader(source: .standardOutput, handle: outputPipe.fileHandleForReading, continuation: continuation, drained: drained)
            let errorReader = LineReader(source: .standardError, handle: errorPipe.fileHandleForReading, continuation: continuation, drained: drained)
            let started = ContinuousClock.now

            // The termination handler can run before the last bytes are read. Wait for both pipes to close first.
            process.terminationHandler = { finished in
                drained.notify(queue: .global()) {
                    continuation.yield(.finished(exitCode: finished.terminationStatus, duration: ContinuousClock.now - started))
                    continuation.finish()
                }
            }

            let handle = ProcessHandle(process)
            continuation.onTermination = { _ in handle.terminateIfRunning() }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: CommandError.launchFailed(
                    executable: command.executable.path,
                    reason: error.localizedDescription
                ))
                return
            }
            outputReader.start()
            errorReader.start()
        }
    }
}

private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminateIfRunning() {
        if process.isRunning { process.terminate() }
    }
}

private final class LineReader: @unchecked Sendable {
    private let source: OutputSource
    private let handle: FileHandle
    private let continuation: AsyncThrowingStream<CommandEvent, Error>.Continuation
    private let drained: DispatchGroup
    private let lock = NSLock()
    private var pending = Data()

    init(
        source: OutputSource,
        handle: FileHandle,
        continuation: AsyncThrowingStream<CommandEvent, Error>.Continuation,
        drained: DispatchGroup
    ) {
        self.source = source
        self.handle = handle
        self.continuation = continuation
        self.drained = drained
        drained.enter()
    }

    func start() {
        handle.readabilityHandler = { [self] readable in
            let data = readable.availableData
            if data.isEmpty {
                readable.readabilityHandler = nil
                flush()
                drained.leave()
            } else {
                consume(data)
            }
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            emit(line)
        }
    }

    private func flush() {
        lock.lock()
        defer { lock.unlock() }
        if !pending.isEmpty {
            emit(pending[...])
            pending.removeAll()
        }
    }

    private func emit(_ line: Data.SubSequence) {
        var bytes = line
        if bytes.last == 0x0D { bytes = bytes.dropLast() }
        continuation.yield(.output(OutputLine(source: source, text: String(decoding: bytes, as: UTF8.self))))
    }
}
