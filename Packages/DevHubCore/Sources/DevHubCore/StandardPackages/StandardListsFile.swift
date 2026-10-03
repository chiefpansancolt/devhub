import Foundation

/// The file that Export writes and Import reads. It holds only the standard lists, not what is installed.
public struct StandardListsFile: Equatable, Sendable {
    public static let format = "devhub-standard-packages"
    public static let version = 1

    public let exportedAt: Date?
    public let lists: StandardPackageLists

    public init(exportedAt: Date?, lists: StandardPackageLists) {
        self.exportedAt = exportedAt
        self.lists = lists
    }

    /// The tools of `lists` that have at least one package, in sidebar order.
    public static func tools(in lists: StandardPackageLists) -> [Bucket] {
        Bucket.allCases.filter { !lists.entries(for: $0).isEmpty }
    }

    /// Builds the file for the chosen tools. A tool with an empty list is left out.
    public static func make(from lists: StandardPackageLists, tools: Set<Bucket>, now: Date) -> StandardListsFile {
        var chosen = StandardPackageLists()
        for bucket in Bucket.allCases where tools.contains(bucket) {
            chosen.set(lists.entries(for: bucket), for: bucket)
        }
        return StandardListsFile(exportedAt: now, lists: chosen)
    }

    // MARK: Reading and writing

    public struct Decoded: Equatable, Sendable {
        public let file: StandardListsFile
        /// Entries of the file that DevHub cannot use, such as a tool or a kind from a newer version, or a name that is not valid.
        public let skippedEntries: Int
    }

    public enum ReadError: Error, Equatable, LocalizedError {
        case unreadable
        case notAStandardPackagesFile
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "The file is not valid JSON.", bundle: .module)
            case .notAStandardPackagesFile:
                String(localized: "This is not a DevHub standard packages file.", bundle: .module)
            case let .newerVersion(version):
                String(localized: "This file was written by a newer version of DevHub (file format \(version)). Update DevHub to read it.", bundle: .module)
            }
        }
    }

    private struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    private struct Payload: Decodable {
        let exportedAt: Date?
        let lists: StandardPackageLists?
        let counts: [String: Count]

        enum CodingKeys: String, CodingKey {
            case exportedAt, lists
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            exportedAt = try? container.decodeIfPresent(Date.self, forKey: .exportedAt)
            lists = try? container.decodeIfPresent(StandardPackageLists.self, forKey: .lists)
            counts = (try? container.decodeIfPresent([String: Count].self, forKey: .lists)) ?? [:]
        }
    }

    /// The number of entries a tool holds in the file, whatever they look like.
    private struct Count: Decodable {
        struct Anything: Decodable {
            init(from decoder: any Decoder) throws {}
        }

        let value: Int

        init(from decoder: any Decoder) throws {
            value = ((try? [Anything](from: decoder)) ?? []).count
        }
    }

    public static func decode(_ data: Data) throws -> Decoded {
        let decoder = HistoryCoding.decoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw ReadError.unreadable }
        guard header.format == format else { throw ReadError.notAStandardPackagesFile }
        let fileVersion = header.version ?? 0
        guard fileVersion <= version else { throw ReadError.newerVersion(fileVersion) }
        guard let payload = try? decoder.decode(Payload.self, from: data) else { throw ReadError.unreadable }

        let lists = payload.lists ?? StandardPackageLists()
        let usable = Bucket.allCases.reduce(0) { $0 + lists.entries(for: $1).count }
        let present = payload.counts.values.reduce(0) { $0 + $1.value }
        return Decoded(file: StandardListsFile(exportedAt: payload.exportedAt, lists: lists), skippedEntries: max(0, present - usable))
    }

    private struct Output: Encodable {
        let format = StandardListsFile.format
        let version = StandardListsFile.version
        let exportedAt: Date?
        let lists: StandardPackageLists
    }

    public func encoded() throws -> Data {
        let encoder = HistoryCoding.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        return try encoder.encode(Output(exportedAt: exportedAt, lists: lists))
    }
}
