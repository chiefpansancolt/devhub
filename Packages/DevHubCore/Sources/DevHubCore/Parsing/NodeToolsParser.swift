import Foundation

enum NodeToolsParser {
    struct InstalledPackage: Equatable {
        let name: String
        let version: String
    }

    private struct PnpmList: Decodable {
        struct Dependency: Decodable {
            let version: String
        }

        let dependencies: [String: Dependency]?
    }

    private struct PnpmOutdated: Decodable {
        let latest: String
    }

    private struct YarnLine: Decodable {
        struct Table: Decodable {
            let head: [String]
            let body: [[String]]
        }

        let type: String
        let table: Table?

        enum CodingKeys: String, CodingKey {
            case type
            case table = "data"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            table = type == "table" ? try container.decode(Table.self, forKey: .table) : nil
        }
    }

    /// `pnpm list -g --json --depth=0`. The output is a list with one entry for the global folder.
    static func parsePnpmInstalled(_ data: Data) throws -> [InstalledPackage] {
        try JSONDecoder().decode([PnpmList].self, from: data)
            .flatMap { $0.dependencies ?? [:] }
            .map { InstalledPackage(name: $0.key, version: $0.value.version) }
            .sorted { $0.name < $1.name }
    }

    /// `pnpm outdated -g --format json`. Prints `{}` when everything is current.
    static func parsePnpmOutdated(_ data: Data) throws -> [String: String] {
        try JSONDecoder().decode([String: PnpmOutdated].self, from: data).mapValues(\.latest)
    }

    /// `yarn global list`. Yarn 1 prints `info "name@1.2.3" has binaries:` for each package, and the name can start with `@`.
    static func parseYarnInstalled(_ text: String) -> [InstalledPackage] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard text.hasPrefix("info \""), let close = text.dropFirst(6).firstIndex(of: "\"") else { return nil }
            return split(text[text.index(text.startIndex, offsetBy: 6)..<close])
        }
        .sorted { $0.name < $1.name }
    }

    /// `yarn global dir`. The folder is the only line on standard output.
    static func parseYarnGlobalFolder(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `yarn outdated --json`. Prints one JSON object per line, and the line of type `table` holds the packages. Nothing is printed when all are current.
    static func parseYarnOutdated(_ text: String) -> [String: String] {
        var updates: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let entry = try? JSONDecoder().decode(YarnLine.self, from: Data(line.utf8)), let table = entry.table,
                  let name = table.head.firstIndex(of: "Package"), let latest = table.head.firstIndex(of: "Latest") else { continue }
            for row in table.body where row.count > max(name, latest) {
                updates[row[name]] = row[latest]
            }
        }
        return updates
    }

    /// `bun pm ls -g`. The first line is the folder, and each package is a tree line such as `├── @scope/name@1.2.3`.
    static func parseBunInstalled(_ text: String) -> [InstalledPackage] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard text.hasPrefix("├── ") || text.hasPrefix("└── ") else { return nil }
            return split(text.dropFirst(4))
        }
        .sorted { $0.name < $1.name }
    }

    /// `bun outdated -g`. A table with the columns Package, Current, Update and Latest.
    static func parseBunOutdated(_ text: String) -> [String: String] {
        var updates: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("| ") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4, cells[0] != "Package" else { continue }
            updates[cells[0]] = cells[3]
        }
        return updates
    }

    // The version follows the last `@`, because a scoped name starts with one.
    private static func split(_ text: Substring) -> InstalledPackage? {
        guard let separator = text.lastIndex(of: "@"), separator != text.startIndex else { return nil }
        return InstalledPackage(name: String(text[..<separator]), version: String(text[text.index(after: separator)...]))
    }
}
