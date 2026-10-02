import Foundation

enum PythonParser {
    struct InstalledTool: Equatable {
        let name: String
        let version: String
    }

    private struct PipxList: Decodable {
        struct Venv: Decodable {
            struct Metadata: Decodable {
                struct MainPackage: Decodable {
                    let package: String
                    let packageVersion: String

                    enum CodingKeys: String, CodingKey {
                        case package
                        case packageVersion = "package_version"
                    }
                }

                let mainPackage: MainPackage

                enum CodingKeys: String, CodingKey {
                    case mainPackage = "main_package"
                }
            }

            let metadata: Metadata
        }

        let venvs: [String: Venv]
    }

    private struct OutdatedPackage: Decodable {
        let name: String
        let latestVersion: String

        enum CodingKeys: String, CodingKey {
            case name
            case latestVersion = "latest_version"
        }
    }

    /// `pipx list --json`. A venv holds one tool and its dependencies, and only the main package is a tool.
    static func parsePipxList(_ data: Data) throws -> [InstalledTool] {
        try JSONDecoder().decode(PipxList.self, from: data).venvs.values
            .map { InstalledTool(name: $0.metadata.mainPackage.package, version: $0.metadata.mainPackage.packageVersion) }
            .sorted { $0.name < $1.name }
    }

    /// `pipx runpip <tool> list --outdated --format=json`. The list holds the dependencies too, so pick the tool by name.
    static func parseLatestVersion(of tool: String, in data: Data) -> String? {
        let packages = (try? JSONDecoder().decode([OutdatedPackage].self, from: data)) ?? []
        return packages.first { normalized($0.name) == normalized(tool) }?.latestVersion
    }

    struct UvEntry: Equatable {
        let tool: InstalledTool
        let latest: String?
        let requirement: String?

        /// `uv tool upgrade` stays inside the requirement the tool was installed with, but `--outdated` reports the newest version overall.
        var latestIsReachable: Bool {
            guard let requirement else { return true }
            return !["==", "<", "~="].contains { requirement.contains($0) }
        }
    }

    /// `uv tool list`. Each tool starts a line such as `ruff v0.5.0`, and the lines that start with `- ` are its programs.
    /// With `--outdated --show-version-specifiers`, a tool ends with `[required: ==0.5.0] [latest: 0.16.10]`, and each part is optional.
    static func parseUvList(_ text: String) -> [UvEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard let first = text.first, !first.isWhitespace, first != "-" else { return nil }
            let parts = text.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[1].hasPrefix("v") else { return nil }
            return UvEntry(
                tool: InstalledTool(name: String(parts[0]), version: String(parts[1].dropFirst())),
                latest: bracketValue("latest", in: text),
                requirement: bracketValue("required", in: text)
            )
        }
    }

    private static func bracketValue(_ label: String, in text: String) -> String? {
        guard let start = text.range(of: "[\(label): ") else { return nil }
        return text[start.upperBound...].firstIndex(of: "]").map { String(text[start.upperBound..<$0]) }
    }

    // PyPI treats `-`, `_` and `.` as the same character in a name.
    private static func normalized(_ name: String) -> String {
        name.lowercased().replacing(/[-_.]+/, with: "-")
    }
}
