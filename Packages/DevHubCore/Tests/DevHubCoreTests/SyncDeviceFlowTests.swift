import Foundation
import Testing
@testable import DevHubCore

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: Double) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private nonisolated(unsafe) let codeAnswer: [String: Any] = [
    "device_code": "dev-123", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5
]

@Suite struct SyncDeviceFlowTests {
    private func flow(_ transport: FakeTransport, sleeps: SleepLog = SleepLog(), clock: Clock = Clock(), onSleep: (@Sendable () -> Void)? = nil) -> GitHubDeviceFlow {
        GitHubDeviceFlow(
            clientID: "client-1", transport: transport,
            sleep: { duration in
                sleeps.add(duration)
                clock.advance(Double(duration.components.seconds))
                onSleep?()
            },
            now: { clock.now }
        )
    }

    @Test func startingAsksForTheRepoScopeWithTheClientID() async throws {
        let transport = FakeTransport { _ in response(200, codeAnswer) }

        let code = try await flow(transport).start()

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(formValues(request) == ["client_id": "client-1", "scope": "repo"])
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURL.absoluteString == "https://github.com/login/device")
    }

    @Test func theCodeExpiresWhenGitHubSaysSo() async throws {
        let clock = Clock()
        let transport = FakeTransport { _ in response(200, codeAnswer) }

        let code = try await flow(transport, clock: clock).start()

        #expect(code.expiresAt == clock.now.addingTimeInterval(900))
    }

    @Test func aFlowThatIsTurnedOffIsReportedAsSuch() async {
        let transport = FakeTransport { _ in response(200, ["error": "device_flow_disabled"]) }

        await #expect(throws: SyncError.deviceFlowDisabled) { try await flow(transport).start() }
    }

    @Test func anAnswerWithoutACodeIsRejected() async {
        let transport = FakeTransport { _ in response(200, ["device_code": "x"]) }

        await #expect(throws: SyncError.unexpectedResponse) { try await flow(transport).start() }
    }

    @Test func pollingWaitsOneIntervalBeforeTheFirstRequestThenKeepsAsking() async throws {
        let sleeps = SleepLog()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            return response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport, sleeps: sleeps)

        let token = try await flow.awaitToken(for: try await flow.start())

        #expect(token == "gho_abc")
        #expect(sleeps.durations == [.seconds(5)])
    }

    @Test func pendingAnswersKeepPollingAtTheSameInterval() async throws {
        let sleeps = SleepLog()
        let answers = Counter()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            return answers.next() < 3 ? response(200, ["error": "authorization_pending"]) : response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport, sleeps: sleeps)

        _ = try await flow.awaitToken(for: try await flow.start())

        #expect(sleeps.durations == [.seconds(5), .seconds(5), .seconds(5), .seconds(5)])
    }

    @Test func slowDownMovesToTheIntervalGitHubSends() async throws {
        let sleeps = SleepLog()
        let answers = Counter()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            return answers.next() == 0 ? response(200, ["error": "slow_down", "interval": 10]) : response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport, sleeps: sleeps)

        _ = try await flow.awaitToken(for: try await flow.start())

        #expect(sleeps.durations == [.seconds(5), .seconds(10)])
    }

    @Test func slowDownWithoutAnIntervalAddsFiveSeconds() async throws {
        let sleeps = SleepLog()
        let answers = Counter()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            return answers.next() == 0 ? response(200, ["error": "slow_down"]) : response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport, sleeps: sleeps)

        _ = try await flow.awaitToken(for: try await flow.start())

        #expect(sleeps.durations == [.seconds(5), .seconds(10)])
    }

    @Test func thePollSendsTheDeviceCodeAndTheGrantType() async throws {
        let transport = FakeTransport { request in
            request.url?.path == "/login/device/code" ? response(200, codeAnswer) : response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport)

        _ = try await flow.awaitToken(for: try await flow.start())

        let poll = try #require(transport.requests.last)
        #expect(poll.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(formValues(poll) == ["client_id": "client-1", "device_code": "dev-123", "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        #expect(String(decoding: poll.httpBody ?? Data(), as: UTF8.self).contains("urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
    }

    @Test(arguments: [("expired_token", SyncError.codeExpired), ("access_denied", SyncError.accessDenied), ("device_flow_disabled", SyncError.deviceFlowDisabled), ("something_new", SyncError.unexpectedResponse)])
    func aTerminalErrorStopsThePolling(error: String, expected: SyncError) async throws {
        let transport = FakeTransport { request in
            request.url?.path == "/login/device/code" ? response(200, codeAnswer) : response(200, ["error": error])
        }
        let flow = flow(transport)
        let code = try await flow.start()

        await #expect(throws: expected) { try await flow.awaitToken(for: code) }
    }

    @Test func aNetworkBlipDuringPollingIsRetried() async throws {
        let polls = Counter()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            if polls.next() == 0 { throw URLError(.networkConnectionLost) }
            return response(200, ["access_token": "gho_abc"])
        }
        let flow = flow(transport)

        let token = try await flow.awaitToken(for: try await flow.start())

        #expect(token == "gho_abc")
    }

    @Test func aCodeThatRanOutOnTheClockStopsWithoutAskingAgain() async throws {
        let clock = Clock()
        let polls = Counter()
        let transport = FakeTransport { request in
            if request.url?.path == "/login/device/code" { return response(200, codeAnswer) }
            return polls.next() < 10 ? response(200, ["error": "authorization_pending"]) : response(200, ["error": "access_denied"])
        }
        let sleeps = SleepLog()
        let flow = flow(transport, sleeps: sleeps, clock: clock) { clock.advance(400) }
        let code = try await flow.start()

        await #expect(throws: SyncError.codeExpired) { try await flow.awaitToken(for: code) }

        #expect(transport.requests.count <= 4)
    }

    @Test func cancellingStopsThePolling() async throws {
        let transport = FakeTransport { request in
            request.url?.path == "/login/device/code" ? response(200, codeAnswer) : response(200, ["error": "authorization_pending"])
        }
        let flow = GitHubDeviceFlow(clientID: "c", transport: transport, sleep: { _ in throw CancellationError() })
        let code = try await GitHubDeviceFlow(clientID: "c", transport: transport).start()

        await #expect(throws: CancellationError.self) { try await flow.awaitToken(for: code) }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
