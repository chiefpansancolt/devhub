import Foundation
import Security

public protocol GitHubTokenStore: Sendable {
    func token() async throws -> String?
    func save(_ token: String) async throws
    func delete() async throws
}

/// Keeps the token in the login keychain. An ad-hoc signed app has no stable identity, so a read can fail after an update, and the sync then asks the user to connect again.
public struct KeychainTokenStore: GitHubTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.chiefpansancolt.devhub.github", account: String = "oauth-token") {
        self.service = service
        self.account = account
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func token() async throws -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound: return nil
        default: throw SyncError.keychain(Self.message(for: status))
        }
    }

    public func save(_ token: String) async throws {
        SecItemDelete(identity as CFDictionary)
        var item = identity
        item[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SyncError.keychain(Self.message(for: status)) }
    }

    public func delete() async throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SyncError.keychain(Self.message(for: status)) }
    }

    private static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
    }
}
