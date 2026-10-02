enum GemParser {
    struct ListEntry: Equatable {
        let name: String
        let versions: [String]
        let defaultVersion: String?

        /// The newest regular version. A default gem that has no other version reports its default version.
        var displayVersion: String? {
            versions.max { PackageVersion($0) < PackageVersion($1) } ?? defaultVersion
        }
    }

    struct OutdatedEntry: Equatable {
        let name: String
        let latest: String
    }

    static func parseList(_ text: String) -> [ListEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let (name, inside) = nameAndParentheses(String(line)) else { return nil }
            var versions: [String] = []
            var defaultVersion: String?
            for item in inside.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if item.hasPrefix("default:") {
                    defaultVersion = item.dropFirst("default:".count).trimmingCharacters(in: .whitespaces)
                } else {
                    versions.append(item.split(separator: " ").first.map(String.init) ?? item)
                }
            }
            let allVersions = versions + (defaultVersion.map { [$0] } ?? [])
            guard !allVersions.isEmpty, allVersions.allSatisfy(startsWithDigit) else { return nil }
            return ListEntry(name: name, versions: versions, defaultVersion: defaultVersion)
        }
    }

    static func parseOutdated(_ text: String) -> [OutdatedEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let (name, inside) = nameAndParentheses(String(line)) else { return nil }
            let sides = inside.components(separatedBy: " < ")
            guard sides.count == 2, startsWithDigit(sides[0]), let latest = sides[1].split(separator: " ").first,
                  startsWithDigit(String(latest)) else { return nil }
            return OutdatedEntry(name: name, latest: String(latest))
        }
    }

    private static func startsWithDigit(_ version: String) -> Bool {
        version.first?.isNumber == true
    }

    /// Gem lines start at the first column. An indented line is part of a warning message.
    private static func nameAndParentheses(_ line: String) -> (name: String, inside: String)? {
        guard line.first?.isWhitespace == false, line.hasSuffix(")"), let open = line.firstIndex(of: "(") else { return nil }
        let name = line[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return nil }
        let inside = line[line.index(after: open)..<line.index(before: line.endIndex)]
        return (name, String(inside))
    }
}
