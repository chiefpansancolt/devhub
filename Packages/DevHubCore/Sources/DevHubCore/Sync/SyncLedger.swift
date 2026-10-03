import Foundation

public struct SyncSummary: Codable, Equatable, Sendable {
    public let added: Int
    public let removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    public var isEmpty: Bool { added == 0 && removed == 0 }
}

public struct SyncFailure: Codable, Equatable, Sendable {
    public let kind: SyncFailureKind
    public let message: String
}

public struct SyncResult: Codable, Equatable, Sendable {
    public let at: Date
    public let summary: SyncSummary?
    public let failure: SyncFailure?

    public static func success(at: Date, summary: SyncSummary) -> SyncResult {
        SyncResult(at: at, summary: summary, failure: nil)
    }

    public static func failed(at: Date, kind: SyncFailureKind, message: String) -> SyncResult {
        SyncResult(at: at, summary: nil, failure: SyncFailure(kind: kind, message: message))
    }
}

/// Remembers the linked account, the lists as they were at the last successful sync, and the last result.
public final class SyncLedger: @unchecked Sendable {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var login: String?
        public var base = StandardPackageLists()
        public var lastResult: SyncResult?
        public var lastSuccessAt: Date?

        public init() {}
    }

    private static let defaultsKey = "syncLedger.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var stored: Snapshot

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    public var snapshot: Snapshot { lock.withLock { stored } }

    /// Links an account. Nothing has been synced yet, so the base is empty and the first sync is a union.
    public func connect(login: String) {
        update { $0 = Snapshot(); $0.login = login }
    }

    public func recordSuccess(base: StandardPackageLists, summary: SyncSummary, at date: Date) {
        update {
            $0.base = base
            $0.lastResult = .success(at: date, summary: summary)
            $0.lastSuccessAt = date
        }
    }

    public func recordFailure(kind: SyncFailureKind, message: String, at date: Date) {
        update { $0.lastResult = .failed(at: date, kind: kind, message: message) }
    }

    public func clear() {
        update { $0 = Snapshot() }
    }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.withLock {
            change(&stored)
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
        }
    }
}
