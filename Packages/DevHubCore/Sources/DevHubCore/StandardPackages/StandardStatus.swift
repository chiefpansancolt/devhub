import Foundation

/// A place the standard packages install into: a Node or Ruby version, a package manager, or the whole Mac for tools without versions.
public struct StandardTarget: Equatable, Hashable, Sendable, Identifiable {
    public let bucket: Bucket
    public let group: String?

    public init(bucket: Bucket, group: String?) {
        self.bucket = bucket
        self.group = group
    }

    public var id: String { "\(bucket.rawValue)/\(group ?? "-")" }

    public var isVersion: Bool {
        group?.first?.isNumber == true
    }
}

public struct StandardTargetStatus: Equatable, Sendable, Identifiable {
    public let target: StandardTarget
    public let total: Int
    public let missing: [StandardEntry]

    public var id: String { target.id }
    public var installed: Int { total - missing.count }
    public var isComplete: Bool { total > 0 && missing.isEmpty }
}

public enum StandardStatus {
    /// The targets of a tool. `groups` are the versions and managers DevHub knows, in sidebar order.
    public static func targets(for bucket: Bucket, groups: [String]) -> [StandardTarget] {
        switch bucket {
        case .homebrew, .rust: [StandardTarget(bucket: bucket, group: nil)]
        case .node, .ruby, .python: groups.map { StandardTarget(bucket: bucket, group: $0) }
        }
    }

    public static func status(
        for bucket: Bucket,
        lists: StandardPackageLists,
        groups: [String],
        packages: [InstalledPackage]
    ) -> [StandardTargetStatus] {
        let entries = lists.entries(for: bucket)
        return targets(for: bucket, groups: groups).map { target in
            let here = packages.filter { $0.bucket == bucket && $0.group == target.group }
            let missing = entries.filter { entry in
                let kind = kind(of: entry, in: target)
                return !here.contains { $0.kind == kind && matches($0.name, entry) }
            }
            return StandardTargetStatus(target: target, total: entries.count, missing: missing)
        }
    }

    /// The package that installing `entry` into `target` would create.
    public static func subject(for entry: StandardEntry, in target: StandardTarget) -> InstalledPackage {
        InstalledPackage(bucket: target.bucket, kind: kind(of: entry, in: target), name: entry.name, group: target.group, installedVersion: "")
    }

    /// Packages that pnpm, Bun and Yarn install have their own kinds, although the list holds plain npm names.
    static func kind(of entry: StandardEntry, in target: StandardTarget) -> PackageKind {
        guard target.bucket == .node, let manager = NodePackageManager.allCases.first(where: { $0.displayName == target.group }) else {
            return entry.kind
        }
        switch manager {
        case .pnpm: return .pnpmGlobal
        case .bun: return .bunGlobal
        case .yarn: return .yarnGlobal
        }
    }

    // rustup lists a toolchain with its target, such as `stable-aarch64-apple-darwin`, while the list holds `stable`.
    private static func matches(_ installedName: String, _ entry: StandardEntry) -> Bool {
        installedName == entry.name || (entry.kind == .rustToolchain && installedName.hasPrefix(entry.name + "-"))
    }

    /// The packages installed in a target, as list entries. What a tool installs by itself is left out, because it is there in every version.
    public static func entries(installedIn target: StandardTarget, packages: [InstalledPackage]) -> [StandardEntry] {
        packages
            .filter { $0.bucket == target.bucket && $0.group == target.group && !isInstalledByTheTool($0) }
            .map { StandardEntry(name: $0.name, kind: listKind(of: $0.kind)) }
            .filter { StandardName.isValid($0.name) }
    }

    private static func isInstalledByTheTool(_ package: InstalledPackage) -> Bool {
        switch package.bucket {
        case .node: ["npm", "corepack"].contains(package.name)
        case .ruby: package.name == "bundler"
        case .rust: package.kind == .rustToolchain && package.name == "rustup"
        case .homebrew: package.kind == .formula && !package.installedOnRequest
        case .python: false
        }
    }

    private static func listKind(of kind: PackageKind) -> PackageKind {
        switch kind {
        case .pnpmGlobal, .bunGlobal, .yarnGlobal: .npmGlobal
        default: kind
        }
    }
}
