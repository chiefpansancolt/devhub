import Foundation

public enum RuntimeReleaseError: Error, Equatable, Sendable {
    case unreadable
    case badStatus(Int)
}

extension RuntimeReleaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The release list could not be read.", bundle: .module)
        case let .badStatus(code): String(localized: "The release list answered with status \(code).", bundle: .module)
        }
    }
}

public protocol RuntimeReleaseFetching: Sendable {
    /// Every stable release of the tool, without a leading `v`, in no particular order.
    func releases(for bucket: Bucket) async throws -> [String]
}

public enum RuntimeReleaseParser {
    public static func parseNode(_ data: Data) throws -> [String] {
        struct Entry: Decodable { let version: String }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { throw RuntimeReleaseError.unreadable }
        return entries.map { $0.version.hasPrefix("v") ? String($0.version.dropFirst()) : $0.version }.filter(isPlainVersion)
    }

    /// Reads the tarball index, which lists each release once per archive format. Previews and release candidates are skipped.
    public static func parseRuby(_ data: Data) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("name\t") else { throw RuntimeReleaseError.unreadable }
        var seen = Set<String>()
        return text.split(separator: "\n").dropFirst().compactMap { row in
            guard let name = row.split(separator: "\t").first, name.hasPrefix("ruby-") else { return nil }
            let version = String(name.dropFirst("ruby-".count))
            return isPlainVersion(version) && seen.insert(version).inserted ? version : nil
        }
    }

    static func isPlainVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return (2...4).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}

public struct OfficialRuntimeReleases: RuntimeReleaseFetching {
    private let fetch: @Sendable (URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data = Self.download) {
        self.fetch = fetch
    }

    public func releases(for bucket: Bucket) async throws -> [String] {
        switch bucket {
        case .node: try RuntimeReleaseParser.parseNode(await fetch(URL(string: "https://nodejs.org/dist/index.json")!))
        case .ruby: try RuntimeReleaseParser.parseRuby(await fetch(URL(string: "https://cache.ruby-lang.org/pub/ruby/index.txt")!))
        default: []
        }
    }

    public static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw RuntimeReleaseError.badStatus(status)
        }
        return data
    }
}
