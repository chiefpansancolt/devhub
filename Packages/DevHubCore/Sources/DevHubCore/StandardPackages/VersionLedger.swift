import Foundation

/// Remembers which Node and Ruby versions existed when DevHub first ran, which offers the user dismissed and which offers were announced.
public final class VersionLedger: @unchecked Sendable {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var baseline: Set<String> = []
        public var dismissed: Set<String> = []
        public var notified: Set<String> = []
        public var isSeeded = false

        public init() {}
    }

    private static let defaultsKey = "versionLedger.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var stored: Snapshot

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    public static func key(_ bucket: Bucket, _ version: String) -> String {
        "\(bucket.rawValue)/\(version)"
    }

    public var snapshot: Snapshot { lock.withLock { stored } }

    /// The first run records the versions that already exist, so they are never offered the standard packages.
    public func seedIfNeeded(with keys: Set<String>) {
        lock.withLock {
            guard !stored.isSeeded else { return }
            stored.baseline = keys
            stored.isSeeded = true
            save()
        }
    }

    public func dismiss(_ key: String) {
        lock.withLock {
            stored.dismissed.insert(key)
            save()
        }
    }

    public func clearDismissals(for bucket: Bucket) {
        lock.withLock {
            let prefix = bucket.rawValue + "/"
            stored.dismissed = stored.dismissed.filter { !$0.hasPrefix(prefix) }
            stored.notified = stored.notified.filter { !$0.hasPrefix(prefix) }
            save()
        }
    }

    public func markNotified(_ keys: Set<String>) {
        lock.withLock {
            stored.notified.formUnion(keys)
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

public struct StandardOffer: Equatable, Sendable, Identifiable {
    public let bucket: Bucket
    public let version: String
    public let missing: [StandardEntry]

    public init(bucket: Bucket, version: String, missing: [StandardEntry]) {
        self.bucket = bucket
        self.version = version
        self.missing = missing
    }

    public var id: String { VersionLedger.key(bucket, version) }
}

public enum StandardPackagePlanner {
    /// Offers to install the standard packages into the Node and Ruby versions that were not there at the first run.
    /// - Parameters:
    ///   - installed: The names found in each version, by tool. A version that is not in the dictionary has not been scanned.
    public static func offers(
        versions: [Bucket: [String]],
        installed: [Bucket: [String: Set<String>]],
        lists: StandardPackageLists,
        ledger: VersionLedger.Snapshot,
        disabledBanners: Set<Bucket>
    ) -> [StandardOffer] {
        guard ledger.isSeeded else { return [] }
        return [Bucket.node, .ruby].filter { !disabledBanners.contains($0) }.flatMap { bucket -> [StandardOffer] in
            let standard = lists.entries(for: bucket)
            guard !standard.isEmpty else { return [] }
            return (versions[bucket] ?? []).compactMap { version in
                let key = VersionLedger.key(bucket, version)
                guard !ledger.baseline.contains(key), !ledger.dismissed.contains(key),
                      let present = installed[bucket]?[version] else { return nil }
                let missing = standard.filter { !present.contains($0.name) }
                return missing.isEmpty ? nil : StandardOffer(bucket: bucket, version: version, missing: missing)
            }
        }
    }
}
