import Foundation
import Testing
@testable import DevHubCore

@Suite struct SyncRepoClientTests {
    private func client(_ transport: FakeTransport, sleeps: SleepLog = SleepLog()) -> GitHubRepoClient {
        GitHubRepoClient(transport: transport, token: "tok-1", sleep: { sleeps.add($0) })
    }

    private func encodedFile(_ text: String, lineBreaks: Bool = false) -> String {
        Data(text.utf8).base64EncodedString(options: lineBreaks ? .lineLength64Characters : [])
    }

    // MARK: Requests

    @Test func everyRequestCarriesTheTokenAndTheGitHubHeaders() async throws {
        let transport = FakeTransport { _ in response(200, ["login": "octo"]) }

        _ = try await client(transport).login()

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DevHub")
    }

    @Test func theLoginIsReadFromTheUser() async throws {
        let transport = FakeTransport { _ in response(200, ["login": "octo", "id": 1]) }

        #expect(try await client(transport).login() == "octo")
    }

    @Test func anAnswerWithoutALoginIsRejected() async {
        let transport = FakeTransport { _ in response(200, ["id": 1]) }

        await #expect(throws: SyncError.unexpectedResponse) { try await client(transport).login() }
    }

    // MARK: Repository

    @Test func anExistingRepositoryIsAdoptedWithoutCreatingOne() async throws {
        let transport = FakeTransport { _ in response(200) }

        let state = try await client(transport).ensureRepository(login: "octo")

        #expect(state == .existing)
        #expect(transport.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == ["GET /repos/octo/devhub-standard-packages"])
    }

    @Test func aMissingRepositoryIsCreatedAsPrivate() async throws {
        let transport = FakeTransport { request in
            request.httpMethod == "GET" ? response(404) : response(201)
        }

        let state = try await client(transport).ensureRepository(login: "octo")

        #expect(state == .created)
        let create = try #require(transport.requests.last)
        #expect(create.httpMethod == "POST")
        #expect(create.url?.path == "/user/repos")
        let body = jsonBody(create)
        #expect(body["name"] as? String == "devhub-standard-packages")
        #expect(body["private"] as? Bool == true)
        #expect(body["auto_init"] as? Bool == true)
    }

    @Test func aNameThatAlreadyExistsOnCreationIsAdopted() async throws {
        let transport = FakeTransport { request in
            request.httpMethod == "GET" ? response(404) : response(422, ["message": "name already exists on this account"])
        }

        #expect(try await client(transport).ensureRepository(login: "octo") == .existing)
    }

    @Test func theRepositoryLinkPointsAtTheAccount() {
        #expect(GitHubRepoClient.repositoryURL(login: "octo").absoluteString == "https://github.com/octo/devhub-standard-packages")
    }

    // MARK: Reading the file

    @Test func theFileIsDecodedFromBase64WithLineBreaks() async throws {
        let text = String(repeating: "standard packages ", count: 12)
        let transport = FakeTransport { _ in response(200, ["content": encodedFile(text, lineBreaks: true), "sha": "abc", "encoding": "base64"]) }

        let file = try #require(try await client(transport).readFile(login: "octo"))

        #expect(String(decoding: file.data, as: UTF8.self) == text)
        #expect(file.sha == "abc")
        #expect(transport.requests.first?.url?.path == "/repos/octo/devhub-standard-packages/contents/standard-packages.json")
    }

    @Test func aMissingFileIsNil() async throws {
        let transport = FakeTransport { _ in response(404) }

        #expect(try await client(transport).readFile(login: "octo") == nil)
    }

    @Test func aFileTooLargeToBeSentInlineIsReported() async {
        let transport = FakeTransport { _ in response(200, ["content": "", "sha": "abc", "encoding": "none"]) }

        await #expect(throws: SyncError.remoteFileNotUsable(.tooLarge)) { try await client(transport).readFile(login: "octo") }
    }

    @Test func anUnreadableFileAnswerIsRejected() async {
        let transport = FakeTransport { _ in response(200, ["content": "%%%", "sha": "abc", "encoding": "base64"]) }

        await #expect(throws: SyncError.unexpectedResponse) { try await client(transport).readFile(login: "octo") }
    }

    // MARK: Writing the file

    @Test func theFileIsWrittenWithTheShaItReplaces() async throws {
        let transport = FakeTransport { _ in response(200, ["content": ["sha": "new1"]]) }

        let sha = try await client(transport).writeFile(Data("hello".utf8), login: "octo", sha: "old1", retryingNotFound: false)

        #expect(sha == "new1")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        let body = jsonBody(request)
        #expect(body["sha"] as? String == "old1")
        #expect(body["content"] as? String == Data("hello".utf8).base64EncodedString())
        #expect((body["message"] as? String)?.isEmpty == false)
    }

    @Test func aNewFileIsWrittenWithoutASha() async throws {
        let transport = FakeTransport { _ in response(201, ["content": ["sha": "new1"]]) }

        _ = try await client(transport).writeFile(Data("hello".utf8), login: "octo", sha: nil, retryingNotFound: false)

        #expect(jsonBody(try #require(transport.requests.first))["sha"] == nil)
    }

    @Test(arguments: [409, 422])
    func aStaleOrMissingShaIsAConflict(status: Int) async {
        let transport = FakeTransport { _ in response(status) }

        await #expect(throws: SyncError.conflict) { try await client(transport).writeFile(Data(), login: "octo", sha: "old", retryingNotFound: false) }
    }

    @Test func aRepositoryThatWasJustCreatedIsRetriedWhileGitHubCatchesUp() async throws {
        let attempts = Counter()
        let sleeps = SleepLog()
        let transport = FakeTransport { _ in attempts.next() < 2 ? response(404) : response(201, ["content": ["sha": "new1"]]) }

        let sha = try await client(transport, sleeps: sleeps).writeFile(Data(), login: "octo", sha: nil, retryingNotFound: true)

        #expect(sha == "new1")
        #expect(sleeps.durations == [.seconds(1), .seconds(1)])
        #expect(transport.requests.count == 3)
    }

    @Test func aRepositoryThatNeverAppearsIsReportedAfterThreeRetries() async {
        let transport = FakeTransport { _ in response(404) }

        await #expect(throws: SyncError.repositoryNotReady) { try await client(transport).writeFile(Data(), login: "octo", sha: nil, retryingNotFound: true) }

        #expect(transport.requests.count == 4)
    }

    @Test func aMissingRepositoryIsNotRetriedWhenItWasNotJustCreated() async {
        let transport = FakeTransport { _ in response(404) }

        await #expect(throws: SyncError.repositoryNotReady) { try await client(transport).writeFile(Data(), login: "octo", sha: nil, retryingNotFound: false) }

        #expect(transport.requests.count == 1)
    }

    // MARK: Failures

    @Test func aRevokedTokenIsUnauthorized() async {
        let transport = FakeTransport { _ in response(401, ["message": "Bad credentials"]) }

        await #expect(throws: SyncError.unauthorized) { try await client(transport).login() }
        await #expect(throws: SyncError.unauthorized) { try await client(transport).readFile(login: "octo") }
    }

    @Test(arguments: [403, 429])
    func aRateLimitOrABlockedAppIsForbiddenWithGitHubsMessage(status: Int) async {
        let transport = FakeTransport { _ in response(status, ["message": "API rate limit exceeded"]) }

        await #expect(throws: SyncError.forbidden("API rate limit exceeded")) { try await client(transport).login() }
    }

    @Test func aServerErrorKeepsItsStatus() async {
        let transport = FakeTransport { _ in response(503) }

        await #expect(throws: SyncError.server(503)) { try await client(transport).login() }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func aNetworkFailureIsOffline(code: URLError.Code) async {
        let transport = FakeTransport { _ in throw URLError(code) }

        await #expect(throws: SyncError.self) { try await client(transport).login() }
        do {
            _ = try await client(transport).login()
        } catch {
            #expect((error as? SyncError)?.kind == .offline)
        }
    }

    @Test func aCancelledRequestIsACancellation() async {
        let transport = FakeTransport { _ in throw URLError(.cancelled) }

        await #expect(throws: CancellationError.self) { try await client(transport).login() }
    }
}

@Suite struct SyncErrorTests {
    @Test func theKindOfEachErrorDrivesTheStatusLine() {
        #expect(SyncError.offline("x").kind == .offline)
        #expect(SyncError.unauthorized.kind == .unauthorized)
        #expect(SyncError.forbidden("x").kind == .refused)
        #expect(SyncError.remoteFileNotUsable(.newerVersion(2)).kind == .newerFile)
        #expect(SyncError.remoteFileNotUsable(.hasUnreadableEntries(3)).kind == .newerFile)
        #expect(SyncError.remoteFileNotUsable(.notOurFile).kind == .other)
        #expect(SyncError.server(500).kind == .other)
        #expect(SyncError.tooManyConflicts.kind == .other)
    }

    @Test func theMessagesSayWhatToDo() {
        #expect(SyncError.unauthorized.errorDescription == "GitHub no longer accepts this sign-in. Connect again to keep syncing.")
        #expect(SyncError.remoteFileNotUsable(.newerVersion(2)).errorDescription == "The file on GitHub was written by a newer version of DevHub. Update DevHub to sync again. Nothing was uploaded.")
        #expect(SyncError.forbidden("API rate limit exceeded").errorDescription == "GitHub refused the request: API rate limit exceeded")
        #expect(SyncError.server(503).errorDescription == "GitHub answered with an error (503).")
    }

    @Test func theLogKeepsTheDetailThatTheMessageLeavesOut() {
        #expect(SyncError.offline("The Internet connection appears to be offline.").logDetail == "The Internet connection appears to be offline.")
        #expect(SyncError.offline("x").errorDescription == "Could not reach GitHub.")
        #expect(SyncError.keychain("User interaction is not allowed.").logDetail == "User interaction is not allowed.")
    }
}
