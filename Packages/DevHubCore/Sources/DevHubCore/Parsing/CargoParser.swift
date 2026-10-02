import Foundation

enum CargoParser {
    struct InstalledTool: Equatable {
        let name: String
        let version: String
        let isFromRegistry: Bool
    }

    /// `cargo install --list`. A line such as `ripgrep v14.1.1:` starts each tool and the indented lines below it are its programs.
    /// A tool installed from a Git repository or a folder has its source in parentheses.
    static func parseInstalled(_ text: String) -> [InstalledTool] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard let first = text.first, !first.isWhitespace, text.hasSuffix(":") else { return nil }

            let heading = text.dropLast()
            let parts = heading.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[1].hasPrefix("v") else { return nil }
            return InstalledTool(
                name: String(parts[0]),
                version: String(parts[1].dropFirst()),
                isFromRegistry: parts.count == 2
            )
        }
    }

    /// `cargo search <name>`. Each result line is `name = "1.2.3"    # description`, and the best match is not always the exact name.
    static func parseLatestVersion(of name: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            let afterQuote = parts[1].drop { $0 != "\"" }.dropFirst()
            if let end = afterQuote.firstIndex(of: "\"") {
                return String(afterQuote[..<end])
            }
        }
        return nil
    }
}
