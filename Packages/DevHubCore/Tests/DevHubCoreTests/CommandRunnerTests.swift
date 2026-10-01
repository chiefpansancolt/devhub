import Foundation
import Testing
@testable import DevHubCore

@Suite struct CommandRunnerTests {
    private let runner = CommandRunner()

    private func shell(_ script: String, environment: [String: String] = ToolEnvironment.make()) -> ToolCommand {
        ToolCommand(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: environment)
    }

    @Test func capturesStandardOutput() async throws {
        let result = try await runner.run(shell("echo hello; echo world"))

        #expect(result.exitCode == 0)
        #expect(result.succeeded)
        #expect(result.standardOutput == "hello\nworld")
        #expect(result.standardError.isEmpty)
    }

    @Test func keepsStandardErrorSeparate() async throws {
        let result = try await runner.run(shell("echo out; echo err 1>&2"))

        #expect(result.standardOutput == "out")
        #expect(result.standardError == "err")
    }

    @Test func aNonZeroExitCodeIsAResultNotAnError() async throws {
        let result = try await runner.run(shell("echo partial; exit 3"))

        #expect(result.exitCode == 3)
        #expect(result.succeeded == false)
        #expect(result.standardOutput == "partial")
    }

    @Test func keepsALastLineThatHasNoNewline() async throws {
        let result = try await runner.run(shell("printf 'a\\nb'"))

        #expect(result.standardOutput == "a\nb")
    }

    @Test func readsLargeOutputWithoutBlocking() async throws {
        let result = try await runner.run(shell("yes line | head -n 200000; yes err | head -n 200000 1>&2"))

        #expect(result.standardOutput.split(separator: "\n").count == 200_000)
        #expect(result.standardError.split(separator: "\n").count == 200_000)
    }

    @Test func usesOnlyTheEnvironmentItIsGiven() async throws {
        let environment = ["PATH": "/usr/bin:/bin", "DEVHUB_TEST": "yes"]

        let result = try await runner.run(shell("echo $DEVHUB_TEST; echo ${HOME:-no-home}", environment: environment))

        #expect(result.standardOutput == "yes\nno-home")
    }

    @Test func throwsWhenTheProgramDoesNotExist() async {
        let command = ToolCommand(executable: URL(filePath: "/nonexistent/tool"), arguments: [], environment: [:])

        await #expect(throws: CommandError.self) {
            try await runner.run(command)
        }
    }

    @Test func streamsEachLineThenAFinishedEvent() async throws {
        var events: [CommandEvent] = []
        for try await event in runner.stream(shell("echo one; echo two")) {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0] == .output(OutputLine(source: .standardOutput, text: "one")))
        #expect(events[1] == .output(OutputLine(source: .standardOutput, text: "two")))
        guard case let .finished(exitCode, _) = events[2] else {
            Issue.record("The last event must be .finished")
            return
        }
        #expect(exitCode == 0)
    }

    @Test func cancellingStopsTheProcess() async throws {
        let started = ContinuousClock.now
        let task = Task { try await runner.run(shell("sleep 30")) }

        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(ContinuousClock.now - started < .seconds(10))
    }
}
