public struct PackageScope: Hashable, Sendable {
    public let bucket: Bucket
    public let group: String?

    public init(bucket: Bucket, group: String? = nil) {
        self.bucket = bucket
        self.group = group
    }

    public func contains(_ package: InstalledPackage) -> Bool {
        guard package.bucket == bucket else { return false }
        guard let group else { return true }
        return bucket.groupsByKind ? package.kind.rawValue == group : package.group == group
    }

    public static func groups(of bucket: Bucket, versions: [String]) -> [PackageScope] {
        if bucket.groupsByKind {
            return bucket.kinds.map { PackageScope(bucket: bucket, group: $0.rawValue) }
        }
        return versions.map { PackageScope(bucket: bucket, group: $0) }
    }
}

extension Bucket {
    /// Homebrew and Rust split their rows by kind of package. Node and Ruby split them by version.
    public var groupsByKind: Bool {
        switch self {
        case .homebrew, .rust: true
        case .node, .ruby, .python: false
        }
    }

    var kinds: [PackageKind] {
        switch self {
        case .homebrew: [.formula, .cask]
        case .rust: [.rustToolchain, .cargoTool]
        case .node: [.npmGlobal]
        case .ruby: [.gem]
        case .python: [.pythonTool]
        }
    }
}
