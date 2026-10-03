public enum RuntimeManager: String, Sendable, CaseIterable {
    case nvm, fnm, volta, asdf, rbenv, rvm, chruby, custom

    public init(_ manager: NodeVersionManager) {
        self = RuntimeManager(rawValue: manager.rawValue) ?? .custom
    }

    public init(_ manager: RubyVersionManager) {
        self = RuntimeManager(rawValue: manager.rawValue) ?? .custom
    }

    /// chruby has no installer and a custom folder has no manager, so DevHub cannot install a version through them.
    public var canInstallVersions: Bool {
        self != .chruby && self != .custom
    }

    /// Volta has no command that removes one version of Node, so DevHub leaves its versions alone.
    public var canUninstallVersions: Bool {
        canInstallVersions && self != .volta
    }
}

public struct RuntimeVersion: Sendable, Equatable {
    public let bucket: Bucket
    public let version: String
    public let manager: RuntimeManager

    public init(bucket: Bucket, version: String, manager: RuntimeManager) {
        self.bucket = bucket
        self.version = version
        self.manager = manager
    }
}

extension Toolchain {
    public var runtimeVersions: [RuntimeVersion] {
        node.map { RuntimeVersion(bucket: .node, version: $0.version, manager: RuntimeManager($0.manager)) }
            + ruby.map { RuntimeVersion(bucket: .ruby, version: $0.version, manager: RuntimeManager($0.manager)) }
    }
}
