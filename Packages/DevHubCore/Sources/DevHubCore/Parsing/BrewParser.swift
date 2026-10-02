import Foundation

enum BrewParser {
    struct OutdatedItem: Equatable {
        let name: String
        let kind: PackageKind
        let currentVersion: String
        let isPinned: Bool
    }

    static func parseOutdated(_ data: Data) throws -> [OutdatedItem] {
        let payload = try JSONDecoder().decode(OutdatedPayload.self, from: data)
        let formulae = payload.formulae.map {
            OutdatedItem(name: $0.name, kind: .formula, currentVersion: $0.currentVersion, isPinned: $0.pinned ?? false)
        }
        let casks = payload.casks.map {
            OutdatedItem(name: $0.name, kind: .cask, currentVersion: $0.currentVersion, isPinned: $0.pinned ?? false)
        }
        return formulae + casks
    }

    static func parseInstalled(_ data: Data, prefix: URL) throws -> [InstalledPackage] {
        let payload = try JSONDecoder().decode(InfoPayload.self, from: data)
        let installedFormulae = payload.formulae.filter { !$0.installed.isEmpty }

        var requiredBy: [String: [String]] = [:]
        for formula in installedFormulae {
            for dependency in formula.activeKeg.runtimeDependencies ?? [] {
                requiredBy[dependency.fullName, default: []].append(formula.name)
            }
        }

        let formulae = installedFormulae.map { formula in
            let keg = formula.activeKeg
            return InstalledPackage(
                bucket: .homebrew,
                kind: .formula,
                name: formula.name,
                installedVersion: keg.version,
                summary: formula.desc,
                homepage: formula.homepage,
                installPath: prefix.appending(path: "Cellar/\(formula.name)/\(keg.version)").path,
                requiredBy: requiredBy[formula.fullName, default: []].sorted(),
                installedOnRequest: keg.installedOnRequest ?? true
            )
        }

        let casks = payload.casks.compactMap { cask -> InstalledPackage? in
            guard let installed = cask.installed else { return nil }
            return InstalledPackage(
                bucket: .homebrew,
                kind: .cask,
                name: cask.token,
                installedVersion: installed,
                summary: cask.desc,
                homepage: cask.homepage,
                installPath: prefix.appending(path: "Caskroom/\(cask.token)/\(installed)").path
            )
        }

        return (formulae + casks).sorted { $0.name < $1.name }
    }

    static func merge(installed: [InstalledPackage], outdated: [OutdatedItem]) -> [InstalledPackage] {
        let outdatedByKey = Dictionary(outdated.map { (Key(kind: $0.kind, name: $0.name), $0) }, uniquingKeysWith: { first, _ in first })
        return installed.map { package in
            guard let item = outdatedByKey[Key(kind: package.kind, name: package.name)] else { return package }
            return package.withUpdate(item.isPinned ? nil : item.currentVersion, isPinned: item.isPinned)
        }
    }

    private struct Key: Hashable {
        let kind: PackageKind
        let name: String
    }
}

private struct OutdatedPayload: Decodable {
    let formulae: [Entry]
    let casks: [Entry]

    struct Entry: Decodable {
        let name: String
        let currentVersion: String
        let pinned: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case currentVersion = "current_version"
            case pinned
        }
    }

    enum CodingKeys: String, CodingKey {
        case formulae
        case casks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = try container.decodeIfPresent([Entry].self, forKey: .formulae) ?? []
        casks = try container.decodeIfPresent([Entry].self, forKey: .casks) ?? []
    }
}

private struct InfoPayload: Decodable {
    let formulae: [Formula]
    let casks: [Cask]

    enum CodingKeys: String, CodingKey {
        case formulae
        case casks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = try container.decodeIfPresent([Formula].self, forKey: .formulae) ?? []
        casks = try container.decodeIfPresent([Cask].self, forKey: .casks) ?? []
    }

    struct Formula: Decodable {
        let name: String
        let fullName: String
        let desc: String?
        let homepage: String?
        let linkedKeg: String?
        let installed: [Keg]

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case desc
            case homepage
            case linkedKeg = "linked_keg"
            case installed
        }

        var activeKeg: Keg {
            installed.first { $0.version == linkedKeg } ?? installed[installed.count - 1]
        }
    }

    struct Keg: Decodable {
        let version: String
        let installedOnRequest: Bool?
        let runtimeDependencies: [Dependency]?

        enum CodingKeys: String, CodingKey {
            case version
            case installedOnRequest = "installed_on_request"
            case runtimeDependencies = "runtime_dependencies"
        }
    }

    struct Dependency: Decodable {
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    struct Cask: Decodable {
        let token: String
        let desc: String?
        let homepage: String?
        let installed: String?
    }
}
