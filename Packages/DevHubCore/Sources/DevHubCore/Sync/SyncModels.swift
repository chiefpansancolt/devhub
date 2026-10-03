import Foundation

public struct DeviceCodeInfo: Equatable, Sendable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
}

public enum SignInState: Equatable, Sendable {
    case idle
    case requesting
    case waiting(DeviceCodeInfo)
    case failed(String)
}

public struct SyncServices: Sendable {
    public var clientID: String
    public var transport: any HTTPTransport
    public var tokenStore: any GitHubTokenStore
    public var ledger: SyncLedger
    public var sleep: @Sendable (Duration) async throws -> Void
    public var pushDelay: Duration

    public init(
        clientID: String,
        transport: any HTTPTransport = URLSessionTransport(),
        tokenStore: any GitHubTokenStore = KeychainTokenStore(),
        ledger: SyncLedger = SyncLedger(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        pushDelay: Duration = .seconds(3)
    ) {
        self.clientID = clientID
        self.transport = transport
        self.tokenStore = tokenStore
        self.ledger = ledger
        self.sleep = sleep
        self.pushDelay = pushDelay
    }
}

struct SyncConfiguration {
    let services: SyncServices
    let lists: @MainActor () -> StandardPackageLists
    let apply: @MainActor (StandardPackageLists) -> Void
}
