import Foundation

enum NpmParser {
    struct GlobalPackage: Equatable {
        let name: String
        let version: String
    }

    struct OutdatedPackage: Equatable {
        let current: String
        let latest: String
    }

    /// `npm ls -g --depth=0 --json`. A machine with no global packages prints an object without `dependencies`.
    static func parseInstalled(_ data: Data) throws -> [GlobalPackage] {
        guard !isBlank(data) else { return [] }
        let payload = try JSONDecoder().decode(ListPayload.self, from: data)
        return (payload.dependencies ?? [:])
            .compactMap { name, entry in entry.version.map { GlobalPackage(name: name, version: $0) } }
            .sorted { $0.name < $1.name }
    }

    struct PublishedVersion: Equatable {
        let version: String
        let nodeRange: String?
    }

    /// `npm view <name>@<range> version engines.node --json`. One match prints an object, several print a list and none print nothing.
    static func parsePublishedVersions(_ data: Data) throws -> [PublishedVersion] {
        guard !isBlank(data) else { return [] }
        let decoder = JSONDecoder()
        // A package that declares no engines in any matching version prints only the version strings.
        if let versions = try? decoder.decode([String].self, from: data) {
            return versions.map { PublishedVersion(version: $0, nodeRange: nil) }
        }
        let entries: [PublishedEntry]
        if let list = try? decoder.decode([PublishedEntry].self, from: data) {
            entries = list
        } else {
            entries = [try decoder.decode(PublishedEntry.self, from: data)]
        }
        return entries.compactMap { entry in entry.version.map { PublishedVersion(version: $0, nodeRange: entry.nodeRange) } }
    }

    /// `npm view <name> versions --json`. Prints a list of version strings, or one string when the package has one version.
    static func parseVersionList(_ data: Data) -> [String] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([String].self, from: data) { return list }
        return (try? decoder.decode(String.self, from: data)).map { [$0] } ?? []
    }

    /// `npm outdated -g --json`. Prints nothing, or `{}`, when every package is current.
    static func parseOutdated(_ data: Data) throws -> [String: OutdatedPackage] {
        guard !isBlank(data) else { return [:] }
        let payload = try JSONDecoder().decode([String: OutdatedEntry].self, from: data)
        return payload.compactMapValues { entry in
            guard let current = entry.current, let latest = entry.latest else { return nil }
            return OutdatedPackage(current: current, latest: latest)
        }
    }

    private static func isBlank(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    }
}

private struct ListPayload: Decodable {
    let dependencies: [String: Entry]?

    struct Entry: Decodable {
        let version: String?
    }
}

private struct OutdatedEntry: Decodable {
    let current: String?
    let latest: String?
}

private struct PublishedEntry: Decodable {
    let version: String?
    let nodeRange: String?

    enum CodingKeys: String, CodingKey {
        case version
        case nodeRange = "engines.node"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decode(String.self, forKey: .version)
        nodeRange = try? container.decode(String.self, forKey: .nodeRange)
    }
}
