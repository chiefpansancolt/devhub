import Foundation
@testable import DevHubCore

func response(_ status: Int, _ object: Any = [String: Any]()) -> HTTPResponse {
    HTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
}

func formValues(_ request: URLRequest) -> [String: String] {
    let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    var values: [String: String] = [:]
    for pair in text.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { values[parts[0]] = parts[1].removingPercentEncoding }
    }
    return values
}

func jsonBody(_ request: URLRequest) -> [String: Any] {
    ((try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]) ?? [:]
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> HTTPResponse

    init(_ handler: @escaping @Sendable (URLRequest) throws -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        return try handler(request)
    }
}

final class FakeTokenStore: GitHubTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var failure: SyncError?
    private(set) var deletions = 0

    init(token: String? = "token-1") { stored = token }

    var current: String? { lock.withLock { stored } }

    func failReads(with error: SyncError?) { lock.withLock { failure = error } }

    func token() async throws -> String? {
        try lock.withLock {
            if let failure { throw failure }
            return stored
        }
    }

    func save(_ token: String) async throws { lock.withLock { stored = token } }

    func delete() async throws {
        lock.withLock {
            stored = nil
            deletions += 1
        }
    }
}

final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var open: Bool

    init(open: Bool = false) { self.open = open }

    var isOpen: Bool { lock.withLock { open } }
    func release() { lock.withLock { open = true } }
    func close() { lock.withLock { open = false } }

    func wait() async throws {
        while !isOpen { try await Task.sleep(for: .milliseconds(2)) }
    }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    var durations: [Duration] { lock.withLock { recorded } }
    func add(_ duration: Duration) { lock.withLock { recorded.append(duration) } }
}

/// A small in-memory GitHub: one user, one repository and one file, with the sha check of the contents API.
final class FakeGitHub: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()
    var login = "octo"

    struct State {
        var repositoryExists = false
        var file: Data?
        var revision = 0
        var requests: [URLRequest] = []
        var createdRepositories = 0
        var puts = 0
        var contentGets = 0
        var offline = false
        var statusOverride: Int?
        var overrideMessage = "rate limit"
        var putNotFoundAnswers = 0
        var getGates: [Gate] = []
        var putGate: Gate?
        var putStatus: Int?
        var putsStarted = 0
        var beforeContentGet: (@Sendable () -> Void)?
        var beforePut: (@Sendable () -> Void)?
        var gate: Gate?
    }

    var puts: Int { lock.withLock { state.puts } }
    var putsStarted: Int { lock.withLock { state.putsStarted } }
    var contentGets: Int { lock.withLock { state.contentGets } }
    var createdRepositories: Int { lock.withLock { state.createdRepositories } }
    var requests: [URLRequest] { lock.withLock { state.requests } }
    var fileData: Data? { lock.withLock { state.file } }
    var remoteLists: StandardPackageLists? { fileData.flatMap { try? StandardListsFile.decode($0).file.lists } }

    func configure(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }

    func setRemote(_ lists: StandardPackageLists) {
        let data = (try? StandardListsFile(exportedAt: nil, lists: lists).encoded()) ?? Data()
        configure {
            $0.repositoryExists = true
            $0.file = data
            $0.revision += 1
        }
    }

    func setRemoteData(_ data: Data) {
        configure {
            $0.repositoryExists = true
            $0.file = data
            $0.revision += 1
        }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (gate, offline, override, beforeGet, beforePut) = lock.withLock { () -> (Gate?, Bool, Int?, (@Sendable () -> Void)?, (@Sendable () -> Void)?) in
            state.requests.append(request)
            return (state.gate, state.offline, state.statusOverride, state.beforeContentGet, state.beforePut)
        }
        if offline { throw URLError(.notConnectedToInternet) }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let isContents = path.hasSuffix("/contents/standard-packages.json")
        if isContents, method == "GET" {
            lock.withLock { state.contentGets += 1 }
            beforeGet?()
            let specific = lock.withLock { () -> Gate? in
                let index = state.contentGets
                return index <= state.getGates.count ? state.getGates[index - 1] : nil
            }
            if let specific { try await specific.wait() } else if let gate { try await gate.wait() }
        }
        if let override { return response(override, ["message": lock.withLock { state.overrideMessage }]) }
        switch (method, path) {
        case ("GET", "/user"):
            return response(200, ["login": login])
        case ("GET", "/repos/\(login)/devhub-standard-packages"):
            return response(lock.withLock { state.repositoryExists } ? 200 : 404)
        case ("POST", "/user/repos"):
            lock.withLock {
                state.repositoryExists = true
                state.createdRepositories += 1
            }
            return response(201)
        case ("GET", _) where isContents:
            return lock.withLock {
                guard let file = state.file else { return response(404) }
                return response(200, ["content": file.base64EncodedString(options: .lineLength64Characters), "sha": "sha\(state.revision)", "encoding": "base64"])
            }
        case ("PUT", _) where isContents:
            lock.withLock { state.putsStarted += 1 }
            if let putGate = lock.withLock({ state.putGate }) { try await putGate.wait() }
            if let status = lock.withLock({ state.putStatus }) { return response(status, ["message": "boom"]) }
            beforePut?()
            let body = jsonBody(request)
            return lock.withLock {
                if state.putNotFoundAnswers > 0 {
                    state.putNotFoundAnswers -= 1
                    return response(404)
                }
                let given = body["sha"] as? String
                if state.file != nil, given != "sha\(state.revision)" { return response(409) }
                if state.file == nil, given != nil { return response(422) }
                state.file = Data(base64Encoded: (body["content"] as? String) ?? "")
                state.revision += 1
                state.puts += 1
                return response(200, ["content": ["sha": "sha\(state.revision)"]])
            }
        default:
            return response(404)
        }
    }
}

func makeLists(_ build: (inout StandardPackageLists) -> Void) -> StandardPackageLists {
    var result = StandardPackageLists()
    build(&result)
    return result
}

func nodeNames(_ lists: StandardPackageLists) -> [String] {
    lists.entries(for: .node).map(\.name)
}
