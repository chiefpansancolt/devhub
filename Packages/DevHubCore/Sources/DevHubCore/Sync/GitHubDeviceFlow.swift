import Foundation

public struct DeviceCode: Equatable, Sendable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    let deviceCode: String
    let interval: Int
}

/// Signs in with GitHub's device flow, which needs no client secret.
public struct GitHubDeviceFlow: Sendable {
    /// Private repositories can only be created with this scope.
    public static let scope = "repo"
    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    private let clientID: String
    private let transport: any HTTPTransport
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        clientID: String,
        transport: any HTTPTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    public func start() async throws -> DeviceCode {
        let response = try await transport.perform(GitHubRequest.make("POST", Self.deviceCodeURL, form: [("client_id", clientID), ("scope", Self.scope)]))
        let json = try GitHubRequest.object(response)
        if let error = json["error"] as? String { throw Self.failure(for: error) }
        guard let device = json["device_code"] as? String,
              let user = json["user_code"] as? String,
              let address = (json["verification_uri"] as? String).flatMap(URL.init(string:)),
              let expires = json["expires_in"] as? Int,
              let interval = json["interval"] as? Int
        else { throw SyncError.unexpectedResponse }
        return DeviceCode(userCode: user, verificationURL: address, expiresAt: now().addingTimeInterval(Double(expires)), deviceCode: device, interval: interval)
    }

    /// Polls until the user approves the code. The first request waits one interval, as GitHub requires.
    public func awaitToken(for code: DeviceCode) async throws -> String {
        var interval = code.interval
        while true {
            try await sleep(.seconds(interval))
            if now() >= code.expiresAt { throw SyncError.codeExpired }
            let response: HTTPResponse
            do {
                response = try await transport.perform(GitHubRequest.make("POST", Self.tokenURL, form: [
                    ("client_id", clientID),
                    ("device_code", code.deviceCode),
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                ]))
            } catch SyncError.offline(_) {
                continue
            }
            let json = try GitHubRequest.object(response)
            if let token = json["access_token"] as? String { return token }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval = (json["interval"] as? Int) ?? interval + 5
            case let error?: throw Self.failure(for: error)
            case nil: throw SyncError.unexpectedResponse
            }
        }
    }

    private static func failure(for error: String) -> SyncError {
        switch error {
        case "expired_token": .codeExpired
        case "access_denied": .accessDenied
        case "device_flow_disabled": .deviceFlowDisabled
        default: .unexpectedResponse
        }
    }
}
