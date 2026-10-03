import Foundation

public struct RemoteFile: Equatable, Sendable {
    public let data: Data
    public let sha: String
}

public enum RepositoryState: Equatable, Sendable {
    case existing
    case created
}

public struct GitHubRepoClient: Sendable {
    public static let repositoryName = "devhub-standard-packages"
    public static let filePath = "standard-packages.json"
    private static let api = "https://api.github.com"
    private static let notFoundRetries = 3

    private let transport: any HTTPTransport
    private let token: String
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(transport: any HTTPTransport, token: String, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.token = token
        self.sleep = sleep
    }

    public static func repositoryURL(login: String) -> URL {
        URL(string: "https://github.com/\(login)/\(repositoryName)")!
    }

    public func login() async throws -> String {
        let response = try await send("GET", "/user")
        guard response.status == 200 else { throw GitHubRequest.error(for: response) }
        guard let login = try GitHubRequest.object(response)["login"] as? String else { throw SyncError.unexpectedResponse }
        return login
    }

    /// Finds the repository, or creates it as a private repository when it does not exist.
    public func ensureRepository(login: String) async throws -> RepositoryState {
        let existing = try await send("GET", "/repos/\(login)/\(Self.repositoryName)")
        switch existing.status {
        case 200: return .existing
        case 404: break
        default: throw GitHubRequest.error(for: existing)
        }
        let created = try await send("POST", "/user/repos", json: [
            "name": Self.repositoryName,
            "private": true,
            "auto_init": true,
            "description": "Standard packages lists synced by DevHub"
        ])
        switch created.status {
        case 201: return .created
        case 422: return .existing
        default: throw GitHubRequest.error(for: created)
        }
    }

    public func readFile(login: String) async throws -> RemoteFile? {
        let response = try await send("GET", contentsPath(login))
        switch response.status {
        case 200:
            let json = try GitHubRequest.object(response)
            guard json["encoding"] as? String == "base64" else { throw SyncError.remoteFileNotUsable(.tooLarge) }
            guard let content = json["content"] as? String, let sha = json["sha"] as? String,
                  let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { throw SyncError.unexpectedResponse }
            return RemoteFile(data: data, sha: sha)
        case 404:
            return nil
        default:
            throw GitHubRequest.error(for: response)
        }
    }

    /// Writes the file and returns its new sha. A stale or missing sha throws `SyncError.conflict`.
    /// - Parameter retryingNotFound: Set for a repository that was just created, which GitHub may not serve at once.
    public func writeFile(_ data: Data, login: String, sha: String?, retryingNotFound: Bool) async throws -> String {
        var body: [String: Any] = ["message": "Update standard packages", "content": data.base64EncodedString()]
        if let sha { body["sha"] = sha }
        for attempt in 0...(retryingNotFound ? Self.notFoundRetries : 0) {
            let response = try await send("PUT", contentsPath(login), json: body)
            switch response.status {
            case 200, 201:
                guard let sha = (try GitHubRequest.object(response)["content"] as? [String: Any])?["sha"] as? String else { throw SyncError.unexpectedResponse }
                return sha
            case 409, 422:
                throw SyncError.conflict
            case 404 where attempt < Self.notFoundRetries && retryingNotFound:
                try await sleep(.seconds(1))
            case 404:
                throw SyncError.repositoryNotReady
            default:
                throw GitHubRequest.error(for: response)
            }
        }
        throw SyncError.repositoryNotReady
    }

    private func contentsPath(_ login: String) -> String {
        "/repos/\(login)/\(Self.repositoryName)/contents/\(Self.filePath)"
    }

    private func send(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> HTTPResponse {
        try await transport.perform(GitHubRequest.make(method, URL(string: Self.api + path)!, token: token, json: json))
    }
}
