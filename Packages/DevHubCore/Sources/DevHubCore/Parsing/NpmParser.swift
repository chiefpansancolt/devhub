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
