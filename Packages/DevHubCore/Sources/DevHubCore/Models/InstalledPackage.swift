public enum PackageKind: String, Sendable, Codable, CaseIterable {
    case formula
    case cask
    case npmGlobal
    case gem
}

public struct InstalledPackage: Identifiable, Sendable, Equatable {
    public let bucket: Bucket
    public let kind: PackageKind
    public let name: String
    /// The Node or Ruby version that holds the package. `nil` for Homebrew.
    public let group: String?
    public let installedVersion: String
    /// The newest version, set only when it differs from the installed version and the package can be updated.
    public let availableUpdate: String?
    public let isPinned: Bool
    public let summary: String?
    public let homepage: String?
    public let installPath: String?
    public let requiredBy: [String]
    /// `false` for packages that were installed only to satisfy another package.
    public let installedOnRequest: Bool

    public init(
        bucket: Bucket,
        kind: PackageKind,
        name: String,
        group: String? = nil,
        installedVersion: String,
        availableUpdate: String? = nil,
        isPinned: Bool = false,
        summary: String? = nil,
        homepage: String? = nil,
        installPath: String? = nil,
        requiredBy: [String] = [],
        installedOnRequest: Bool = true
    ) {
        self.bucket = bucket
        self.kind = kind
        self.name = name
        self.group = group
        self.installedVersion = installedVersion
        self.availableUpdate = availableUpdate
        self.isPinned = isPinned
        self.summary = summary
        self.homepage = homepage
        self.installPath = installPath
        self.requiredBy = requiredBy
        self.installedOnRequest = installedOnRequest
    }

    public var id: String { "\(bucket.rawValue)/\(group ?? "-")/\(kind.rawValue)/\(name)" }

    public var isOutdated: Bool { availableUpdate != nil }

    func withUpdate(_ version: String?, isPinned: Bool) -> InstalledPackage {
        InstalledPackage(
            bucket: bucket, kind: kind, name: name, group: group, installedVersion: installedVersion,
            availableUpdate: version, isPinned: isPinned, summary: summary, homepage: homepage,
            installPath: installPath, requiredBy: requiredBy, installedOnRequest: installedOnRequest
        )
    }
}

public struct ScanIssue: Sendable, Equatable, Identifiable {
    /// The Node or Ruby version the problem belongs to. `nil` when it affects the whole bucket.
    public let group: String?
    public let message: String

    public init(group: String?, message: String) {
        self.group = group
        self.message = message
    }

    public var id: String { "\(group ?? "-"): \(message)" }
}

public struct ScanResult: Sendable, Equatable {
    public let packages: [InstalledPackage]
    public let issues: [ScanIssue]

    public init(packages: [InstalledPackage], issues: [ScanIssue] = []) {
        self.packages = packages
        self.issues = issues
    }
}

enum ScanFailure: Error, Equatable {
    case commandFailed(command: String, exitCode: Int32, detail: String)
    case unreadableOutput(command: String, reason: String)

    var message: String {
        switch self {
        case let .commandFailed(command, exitCode, detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "\(command) exited with code \(exitCode)\(suffix)"
        case let .unreadableOutput(command, reason):
            return "Could not read the output of \(command): \(reason)"
        }
    }
}
