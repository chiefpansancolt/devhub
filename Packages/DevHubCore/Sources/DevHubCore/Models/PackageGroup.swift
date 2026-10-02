import Foundation

enum PackageGroup {
    /// Versions come first and the newest is first. Names such as `pnpm` or `uv` follow in alphabetical order.
    static func precedes(_ left: String, _ right: String) -> Bool {
        let leftIsVersion = left.first?.isNumber == true
        let rightIsVersion = right.first?.isNumber == true
        if leftIsVersion != rightIsVersion { return leftIsVersion }
        if leftIsVersion { return PackageVersion(left) > PackageVersion(right) }
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }
}
