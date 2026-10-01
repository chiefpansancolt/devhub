/// The part of a bucket the window shows: the whole bucket, or one Node or Ruby version, or one Homebrew kind.
public struct PackageScope: Hashable, Sendable {
    public let bucket: Bucket
    /// A Node or Ruby version, or `formula` or `cask` for Homebrew. `nil` means the whole bucket.
    public let group: String?

    public init(bucket: Bucket, group: String? = nil) {
        self.bucket = bucket
        self.group = group
    }

    public func contains(_ package: InstalledPackage) -> Bool {
        guard package.bucket == bucket else { return false }
        guard let group else { return true }
        return bucket == .homebrew ? package.kind.rawValue == group : package.group == group
    }

    /// The scopes for the sidebar rows under a bucket, not counting the whole bucket.
    public static func groups(of bucket: Bucket, versions: [String]) -> [PackageScope] {
        switch bucket {
        case .homebrew:
            [PackageScope(bucket: .homebrew, group: PackageKind.formula.rawValue), PackageScope(bucket: .homebrew, group: PackageKind.cask.rawValue)]
        case .node, .ruby:
            versions.map { PackageScope(bucket: bucket, group: $0) }
        }
    }
}
