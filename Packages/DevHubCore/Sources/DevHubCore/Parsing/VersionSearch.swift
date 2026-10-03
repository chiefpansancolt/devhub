import Foundation

enum VersionSearch {
    /// The versions worth checking when the newest one does not suit: the newest patch of every minor version below `latest`, newest first.
    /// Prereleases are left out. Checking one version for each minor keeps the number of lookups small.
    static func candidates(below latest: String, among versions: [String]) -> [String] {
        let limit = PackageVersion(latest)
        var newestOfMinor: [String: PackageVersion] = [:]
        for text in versions where !text.contains("-") {
            let version = PackageVersion(text)
            guard version < limit, let minor = minorKey(of: text) else { continue }
            if newestOfMinor[minor].map({ $0 < version }) ?? true { newestOfMinor[minor] = version }
        }
        return newestOfMinor.values.sorted(by: >).map(\.text)
    }

    private static func minorKey(of version: String) -> String? {
        let numbers = version.split(separator: ".").prefix(2)
        guard numbers.count == 2, numbers.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return numbers.joined(separator: ".")
    }
}
