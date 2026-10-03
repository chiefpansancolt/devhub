import Foundation
@testable import DevHubCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    private static func url(_ name: String) -> URL {
        Bundle.module.resourceURL!.appending(path: "Fixtures/\(name)")
    }
}

final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ToolCommand] = []
    private let handler: @Sendable (ToolCommand) -> CommandResult

    init(_ handler: @escaping @Sendable (ToolCommand) -> CommandResult) {
        self.handler = handler
    }

    var commands: [ToolCommand] {
        lock.withLock { recorded }
    }

    func run(_ command: ToolCommand) async throws -> CommandResult {
        lock.withLock { recorded.append(command) }
        return handler(command)
    }

    func stream(_ command: ToolCommand) -> AsyncThrowingStream<CommandEvent, Error> {
        lock.withLock { recorded.append(command) }
        return AsyncThrowingStream { continuation in
            let result = handler(command)
            for line in result.standardOutput.split(separator: "\n") {
                continuation.yield(.output(OutputLine(source: .standardOutput, text: String(line))))
            }
            for line in result.standardError.split(separator: "\n") {
                continuation.yield(.output(OutputLine(source: .standardError, text: String(line))))
            }
            continuation.yield(.finished(exitCode: result.exitCode, duration: result.duration))
            continuation.finish()
        }
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

func succeeded(_ standardOutput: String, standardError: String = "") -> CommandResult {
    CommandResult(exitCode: 0, standardOutput: standardOutput, standardError: standardError)
}

func failed(exitCode: Int32, standardError: String) -> CommandResult {
    CommandResult(exitCode: exitCode, standardOutput: "", standardError: standardError)
}

struct TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "devhub-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func makeExecutable(_ relativePath: String) throws {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    func makeFolder(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: url.appending(path: relativePath), withIntermediateDirectories: true)
    }
}
