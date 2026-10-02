import Foundation

enum RustupParser {
    struct InstalledToolchain: Equatable {
        let name: String
        let path: String?
    }

    struct ToolchainStatus: Equatable {
        let name: String
        let installedVersion: String
        let availableVersion: String?
    }

    /// `rustup toolchain list -v`. Each line is `name (flags) path`, and the flags are optional.
    static func parseToolchains(_ text: String) -> [InstalledToolchain] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("info:"), !text.hasPrefix("error:") else { return nil }
            let name = String(text.prefix { !$0.isWhitespace })
            var rest = text.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("("), let close = rest.firstIndex(of: ")") {
                rest = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
            }
            return InstalledToolchain(name: name, path: rest.isEmpty ? nil : rest)
        }
    }

    /// `rustup check`. Prints one line for each toolchain and one for rustup itself, and exits with 100 when an update exists.
    static func parseCheck(_ text: String) -> [ToolchainStatus] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard let separator = text.range(of: " - ") else { return nil }
            let name = String(text[..<separator.lowerBound])
            let detail = String(text[separator.upperBound...])
            guard let colon = detail.firstIndex(of: ":") else { return nil }

            let state = detail[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let versions = detail[detail.index(after: colon)...].components(separatedBy: " -> ")
            guard let installed = firstToken(of: versions[0]), state == "up to date" || state == "update available" else {
                return nil
            }
            let available = versions.count > 1 && state == "update available" ? firstToken(of: versions[1]) : nil
            return ToolchainStatus(name: name, installedVersion: installed, availableVersion: available)
        }
    }

    /// `rustc --version`, for example `rustc 1.98.1 (48a229cea 2026-09-01)`.
    static func parseCompilerVersion(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isNewline).first?.split(separator: " ") ?? []
        return words.count >= 2 && words[0] == "rustc" ? String(words[1]) : nil
    }

    private static func firstToken(of text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
