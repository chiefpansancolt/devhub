import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    public init() {}

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.unexpectedResponse }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}

extension HTTPTransport {
    /// Sends a request and turns a network failure into `SyncError.offline`, and a cancelled request into `CancellationError`.
    func perform(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await send(request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw SyncError.offline(error.localizedDescription)
        }
    }
}

enum GitHubRequest {
    static func make(_ method: String, _ url: URL, token: String? = nil, form: [(String, String)]? = nil, json: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DevHub", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let form {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(encoded(form).utf8)
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encoded(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value)"
        }.joined(separator: "&")
    }

    static func object(_ response: HTTPResponse) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] else { throw SyncError.unexpectedResponse }
        return object
    }

    /// The error for an answer that the caller did not handle itself.
    static func error(for response: HTTPResponse) -> SyncError {
        switch response.status {
        case 401: .unauthorized
        case 403, 429: .forbidden((try? object(response)["message"] as? String) ?? "")
        case 409: .conflict
        case 500...: .server(response.status)
        default: .unexpectedResponse
        }
    }
}
