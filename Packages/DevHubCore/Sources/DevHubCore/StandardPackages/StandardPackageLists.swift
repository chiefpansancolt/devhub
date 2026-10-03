import Foundation

public struct StandardEntry: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var kind: PackageKind

    public init(name: String, kind: PackageKind) {
        self.name = name
        self.kind = kind
    }

    public var id: String { "\(kind.rawValue)/\(name)" }
}

public enum StandardName {
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@/._+-")
    private static let longest = 214

    /// A name becomes a command line argument, so it must not look like an option and must not hold spaces or shell characters.
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= longest, !name.hasPrefix("-") else { return false }
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Splits pasted text at spaces, commas and new lines.
    public static func names(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ", \t\n\r")).filter { !$0.isEmpty }
    }
}

public struct StandardPackageLists: Codable, Equatable, Sendable {
    private var entriesByTool: [String: [StandardEntry]] = [:]

    public init() {}

    public static func allowedKinds(for bucket: Bucket) -> [PackageKind] {
        switch bucket {
        case .homebrew: [.formula, .cask]
        case .node: [.npmGlobal]
        case .ruby: [.gem]
        case .rust: [.rustToolchain, .cargoTool]
        case .python: [.pythonTool]
        }
    }

    public func entries(for bucket: Bucket) -> [StandardEntry] {
        entriesByTool[bucket.rawValue] ?? []
    }

    public var isEmpty: Bool {
        entriesByTool.values.allSatisfy(\.isEmpty)
    }

    /// A tool with an empty list and a tool without an entry are the same, because the file format leaves empty lists out.
    public static func == (left: StandardPackageLists, right: StandardPackageLists) -> Bool {
        left.entriesByTool.filter { !$0.value.isEmpty } == right.entriesByTool.filter { !$0.value.isEmpty }
    }

    public mutating func set(_ entries: [StandardEntry], for bucket: Bucket) {
        entriesByTool[bucket.rawValue] = Self.normalized(entries, for: bucket)
    }

    /// Adds the valid names that are not in the list yet and returns the names that were not valid.
    @discardableResult
    public mutating func add(_ names: [String], kind: PackageKind, to bucket: Bucket) -> [String] {
        let invalid = names.filter { !StandardName.isValid($0) }
        let valid = names.filter(StandardName.isValid)
        set(entries(for: bucket) + valid.map { StandardEntry(name: $0, kind: kind) }, for: bucket)
        return invalid
    }

    public mutating func remove(_ entry: StandardEntry, from bucket: Bucket) {
        set(entries(for: bucket).filter { $0 != entry }, for: bucket)
    }

    private static func normalized(_ entries: [StandardEntry], for bucket: Bucket) -> [StandardEntry] {
        let kinds = allowedKinds(for: bucket)
        var seen = Set<StandardEntry>()
        let unique = entries.filter { kinds.contains($0.kind) && StandardName.isValid($0.name) && seen.insert($0).inserted }
        return unique.sorted { left, right in
            if left.kind != right.kind { return kinds.firstIndex(of: left.kind)! < kinds.firstIndex(of: right.kind)! }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    // MARK: Codable

    private struct LenientEntry: Decodable {
        let entry: StandardEntry?

        init(from decoder: any Decoder) throws {
            entry = try? StandardEntry(from: decoder)
        }
    }

    private struct LenientList: Decodable {
        let entries: [StandardEntry]

        init(from decoder: any Decoder) throws {
            entries = ((try? [LenientEntry](from: decoder)) ?? []).compactMap(\.entry)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stored = (try? container.decode([String: LenientList].self)) ?? [:]
        for (key, list) in stored {
            guard let bucket = Bucket(rawValue: key) else { continue }
            set(list.entries, for: bucket)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entriesByTool.filter { !$0.value.isEmpty })
    }
}
