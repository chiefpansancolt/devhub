import Foundation

/// The `engines.node` range of an npm package, for example `^20.19.0 || ^22.13.0 || >=24`.
struct NodeEngineRange {
    private struct Version: Comparable {
        var major: Int
        var minor: Int
        var patch: Int

        static let zero = Version(major: 0, minor: 0, patch: 0)

        static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    private enum Bound {
        case atLeast(Version)
        case above(Version)
        case atMost(Version)
        case below(Version)

        func allows(_ version: Version) -> Bool {
            switch self {
            case let .atLeast(bound): version >= bound
            case let .above(bound): version > bound
            case let .atMost(bound): version <= bound
            case let .below(bound): version < bound
            }
        }
    }

    private let alternatives: [[Bound]]?

    /// A range that is missing or that DevHub cannot read allows every version.
    init(_ text: String?) {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            alternatives = []
            return
        }
        let parsed = text.components(separatedBy: "||").map { Self.parseSet($0) }
        alternatives = parsed.contains { $0 == nil } ? nil : parsed.compactMap { $0 }
    }

    func allows(_ nodeVersion: String) -> Bool {
        guard let alternatives, !alternatives.isEmpty, let version = Self.parseExact(nodeVersion) else { return true }
        return alternatives.contains { set in set.allSatisfy { $0.allows(version) } }
    }

    private static func parseExact(_ text: String) -> Version? {
        guard let partial = parsePartial(text), partial.count == 3 else { return nil }
        return Version(major: partial[0], minor: partial[1], patch: partial[2])
    }

    /// The leading numbers of a version. A wildcard such as `x` or `*` ends the list.
    private static func parsePartial(_ text: String) -> [Int]? {
        var text = text
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) { text = String(text[..<cut]) }
        var numbers: [Int] = []
        for piece in text.split(separator: ".", omittingEmptySubsequences: false) {
            if ["x", "X", "*", ""].contains(String(piece)) { break }
            guard let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        return numbers.count <= 3 ? numbers : nil
    }

    private static func lower(_ numbers: [Int]) -> Version {
        Version(major: numbers.indices.contains(0) ? numbers[0] : 0, minor: numbers.indices.contains(1) ? numbers[1] : 0, patch: numbers.indices.contains(2) ? numbers[2] : 0)
    }

    /// The first version after every version that matches the partial. `nil` when the partial matches everything.
    private static func upper(_ numbers: [Int]) -> Version? {
        switch numbers.count {
        case 0: nil
        case 1: Version(major: numbers[0] + 1, minor: 0, patch: 0)
        case 2: Version(major: numbers[0], minor: numbers[1] + 1, patch: 0)
        default: Version(major: numbers[0], minor: numbers[1], patch: numbers[2] + 1)
        }
    }

    private static func parseSet(_ text: String) -> [Bound]? {
        var text = text.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: #"(>=|<=|>|<|=|\^|~)\s+"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+-\s+"#, with: " - ", options: .regularExpression)
        var tokens = text.split(separator: " ").map(String.init)
        var bounds: [Bound] = []

        if let dash = tokens.firstIndex(of: "-"), dash > 0, dash + 1 < tokens.count {
            guard let from = parsePartial(tokens[dash - 1]), let to = parsePartial(tokens[dash + 1]) else { return nil }
            bounds.append(.atLeast(lower(from)))
            bounds.append(upper(to).map(Bound.below) ?? .atMost(lower(to)))
            tokens.removeSubrange((dash - 1)...(dash + 1))
        }

        for token in tokens {
            guard let parsed = parseToken(token) else { return nil }
            bounds += parsed
        }
        return bounds
    }

    private static func parseToken(_ token: String) -> [Bound]? {
        let operators = [">=", "<=", ">", "<", "=", "^", "~"]
        let op = operators.first { token.hasPrefix($0) } ?? ""
        guard let numbers = parsePartial(String(token.dropFirst(op.count))) else { return nil }
        let isExact = numbers.count == 3

        switch op {
        case ">=":
            return [.atLeast(lower(numbers))]
        case ">":
            if isExact { return [.above(lower(numbers))] }
            return upper(numbers).map { [.atLeast($0)] } ?? []
        case "<=":
            if isExact { return [.atMost(lower(numbers))] }
            return upper(numbers).map { [.below($0)] } ?? []
        case "<":
            return numbers.isEmpty ? [.below(.zero)] : [.below(lower(numbers))]
        case "^":
            return caret(numbers)
        case "~":
            guard !numbers.isEmpty else { return [] }
            let end = numbers.count == 1
                ? Version(major: numbers[0] + 1, minor: 0, patch: 0)
                : Version(major: numbers[0], minor: numbers[1] + 1, patch: 0)
            return [.atLeast(lower(numbers)), .below(end)]
        default:
            guard !numbers.isEmpty else { return [] }
            return [.atLeast(lower(numbers))] + (upper(numbers).map { [.below($0)] } ?? [])
        }
    }

    private static func caret(_ numbers: [Int]) -> [Bound]? {
        guard let major = numbers.first else { return [] }
        let minor = numbers.count > 1 ? numbers[1] : 0
        let patch = numbers.count > 2 ? numbers[2] : 0
        let end: Version
        if major > 0 || numbers.count == 1 {
            end = Version(major: major + 1, minor: 0, patch: 0)
        } else if minor > 0 || numbers.count == 2 {
            end = Version(major: 0, minor: minor + 1, patch: 0)
        } else {
            end = Version(major: 0, minor: 0, patch: patch + 1)
        }
        return [.atLeast(lower(numbers)), .below(end)]
    }
}
