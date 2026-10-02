import Foundation

enum InstallationAliases {
    static func removing<Installation>(from installations: [Installation], root: (Installation) -> URL) -> [Installation] {
        func isAlias(_ installation: Installation) -> Bool {
            (try? root(installation).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        }
        var seen = Set<String>()
        return (installations.filter { !isAlias($0) } + installations.filter(isAlias))
            .filter { seen.insert(root($0).resolvingSymlinksInPath().path).inserted }
    }
}
