import Foundation

public struct RuntimeOffer: Equatable, Sendable, Identifiable {
    public let bucket: Bucket
    public let version: String
    public let manager: RuntimeManager
    /// The newest installed version in the same line, or the newest installed version when the line is new.
    public let installedVersion: String

    public init(bucket: Bucket, version: String, manager: RuntimeManager, installedVersion: String) {
        self.bucket = bucket
        self.version = version
        self.manager = manager
        self.installedVersion = installedVersion
    }

    public var id: String { VersionLedger.runtimeKey(bucket, version) }
}

public enum RuntimeUpdatePlanner {
    /// Offers the newest release of every installed line, and the newest release overall, when it is not installed.
    /// A line is the major version for Node and the major and minor version for Ruby.
    public static func offers(
        bucket: Bucket,
        installed: [RuntimeVersion],
        releases: [String],
        dismissed: Set<String>
    ) -> [RuntimeOffer] {
        let installable = installed.filter { $0.bucket == bucket && $0.manager.canInstallVersions && RuntimeReleaseParser.isPlainVersion($0.version) }
        guard let highest = installable.max(by: { PackageVersion($0.version) < PackageVersion($1.version) }) else { return [] }
        let stable = releases.filter(RuntimeReleaseParser.isPlainVersion)
        let installedVersions = Set(installed.filter { $0.bucket == bucket }.map(\.version))

        func newest<S: Sequence>(_ versions: S) -> String? where S.Element == String {
            versions.max { PackageVersion($0) < PackageVersion($1) }
        }
        func newestInstalled(inLineOf version: String) -> RuntimeVersion? {
            installable.filter { line(of: $0.version, bucket: bucket) == line(of: version, bucket: bucket) }
                .max { PackageVersion($0.version) < PackageVersion($1.version) }
        }

        var candidates = Set(installable.compactMap { installedVersion in
            newest(stable.filter { line(of: $0, bucket: bucket) == line(of: installedVersion.version, bucket: bucket) })
        })
        if let overall = newest(stable) { candidates.insert(overall) }

        return candidates.compactMap { candidate -> RuntimeOffer? in
            guard !installedVersions.contains(candidate), !dismissed.contains(VersionLedger.runtimeKey(bucket, candidate)) else { return nil }
            let sameLine = newestInstalled(inLineOf: candidate)
            let current = sameLine ?? highest
            guard PackageVersion(current.version) < PackageVersion(candidate) else { return nil }
            return RuntimeOffer(bucket: bucket, version: candidate, manager: current.manager, installedVersion: current.version)
        }
        .sorted { PackageVersion($1.version) < PackageVersion($0.version) }
    }

    static func line(of version: String, bucket: Bucket) -> String {
        version.split(separator: ".").prefix(bucket == .ruby ? 2 : 1).joined(separator: ".")
    }
}
