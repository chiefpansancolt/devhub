public struct PackageVersion: Comparable, Sendable, CustomStringConvertible {
    public let text: String
    private let parts: [Part]

    private enum Part: Equatable {
        case number(Int)
        case word(String)
    }

    public init(_ text: String) {
        self.text = text
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        parts = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { piece in
                if let number = Int(piece) { .number(number) } else { .word(String(piece)) }
            }
    }

    public var description: String { text }

    /// The first number of the version, for example 2 for `2.47.0`. `nil` when the version does not start with a number.
    public var major: Int? {
        if case let .number(value)? = parts.first { value } else { nil }
    }

    public static func == (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : nil
            let right = index < rhs.parts.count ? rhs.parts[index] : nil
            switch (left, right) {
            case let (.number(a)?, .number(b)?):
                if a != b { return a < b }
            case let (.number(a)?, nil):
                if a != 0 { return false }
            case let (nil, .number(b)?):
                if b != 0 { return true }
            case (.word?, nil):
                return true
            case (nil, .word?):
                return false
            case let (.word(a)?, .word(b)?):
                if a != b { return a < b }
            case (.number?, .word?):
                return false
            case (.word?, .number?):
                return true
            case (nil, nil):
                break
            }
        }
        return false
    }
}
