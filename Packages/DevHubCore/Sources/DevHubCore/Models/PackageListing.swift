import Foundation

public enum PackageListMode: Sendable, Equatable {
    case updates
    case allInstalled
}

public enum PackageListing {
    public static func rows(from packages: [InstalledPackage], mode: PackageListMode, search: String) -> [InstalledPackage] {
        switch mode {
        case .updates:
            return packages.filter(\.isOutdated)
        case .allInstalled:
            let query = search.trimmingCharacters(in: .whitespaces)
            let matching = query.isEmpty ? packages : packages.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matching.sorted { left, right in
                if left.isOutdated != right.isOutdated { return left.isOutdated }
                if left.group != right.group { return PackageVersion(left.group ?? "") > PackageVersion(right.group ?? "") }
                return left.name < right.name
            }
        }
    }
}
