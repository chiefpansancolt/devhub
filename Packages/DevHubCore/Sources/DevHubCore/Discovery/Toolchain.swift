import Foundation

/// The options of every scanner, read from the settings.
public struct ScannerOptions: Sendable, Equatable {
    public var homebrew = HomebrewOptions()
    public var node = NodeOptions()
    public var ruby = RubyOptions()

    public init() {}

    public init(_ settings: SettingsValues) {
        homebrew = HomebrewOptions(
            refreshIndexFirst: settings.brewRefreshIndex,
            includeSelfUpdatingCasks: settings.brewIncludeSelfUpdatingCasks,
            includeCasks: settings.brewIncludeCasks,
            cleanupAfterUpdate: settings.brewCleanupAfterUpdate
        )
        node = NodeOptions(includeNpm: settings.nodeIncludeNpm)
        ruby = RubyOptions(installDocumentation: settings.gemInstallDocumentation)
    }
}

/// The package managers found on this Mac.
public struct Toolchain: Sendable {
    public var homebrew: HomebrewInstallation?
    public var node: [NodeInstallation]
    public var ruby: [RubyInstallation]
    /// Why a path the person chose does not work. It replaces the usual message for that bucket.
    private var chosenPathProblems: [Bucket: String]
    /// The tools the person turned off. They have no installation and no setup problem.
    public private(set) var disabled: Set<Bucket>

    public init(
        homebrew: HomebrewInstallation?,
        node: [NodeInstallation],
        ruby: [RubyInstallation],
        chosenPathProblems: [Bucket: String] = [:],
        disabled: Set<Bucket> = []
    ) {
        self.homebrew = homebrew
        self.node = node
        self.ruby = ruby
        self.chosenPathProblems = chosenPathProblems
        self.disabled = disabled
    }

    public static func detect() -> Toolchain {
        detect(settings: SettingsValues())
    }

    /// Looks where the settings say. A path the person chose replaces the usual search for that bucket.
    /// Versions that the person turned off are left out, unless `applyingExclusions` is `false`.
    /// Tools that the person turned off are left out, unless `includingDisabledTools` is `true`. The Settings screen
    /// uses that to say whether a tool is on this Mac even when it is turned off.
    public static func detect(settings: SettingsValues, applyingExclusions: Bool = true, includingDisabledTools: Bool = false) -> Toolchain {
        var problems: [Bucket: String] = [:]

        var homebrew = HomebrewLocator.locate()
        if let path = settings.brewPath {
            if FileManager.default.isExecutableFile(atPath: path) {
                homebrew = HomebrewInstallation(executable: URL(filePath: path))
            } else {
                homebrew = nil
                problems[.homebrew] = String(localized: "There is no brew program at \(path).", bundle: .module)
            }
        }

        var node = NodeVersionDiscovery(versionsFolder: settings.nodeFolder.map { URL(filePath: $0) }).installations()
        if let path = settings.nodeFolder, node.isEmpty {
            problems[.node] = String(localized: "No Node versions were found in \(path).", bundle: .module)
        }
        if applyingExclusions, !node.isEmpty {
            node.removeAll { settings.excludedNodeVersions.contains($0.version) }
            if node.isEmpty { problems[.node] = String(localized: "Every Node version is turned off in Settings.", bundle: .module) }
        }

        var ruby = RubyVersionDiscovery(versionsFolder: settings.rubyFolder.map { URL(filePath: $0) }).installations()
        if let path = settings.rubyFolder, ruby.isEmpty {
            problems[.ruby] = String(localized: "No Ruby versions were found in \(path).", bundle: .module)
        }
        if applyingExclusions, !ruby.isEmpty {
            ruby.removeAll { settings.excludedRubyVersions.contains($0.version) }
            if ruby.isEmpty { problems[.ruby] = String(localized: "Every Ruby version is turned off in Settings.", bundle: .module) }
        }

        var toolchain = Toolchain(homebrew: homebrew, node: node, ruby: ruby, chosenPathProblems: problems)
        if !includingDisabledTools {
            toolchain.turnOff(settings.disabledBuckets)
        }
        return toolchain
    }

    private mutating func turnOff(_ buckets: Set<Bucket>) {
        disabled = buckets
        if buckets.contains(.homebrew) { homebrew = nil }
        if buckets.contains(.node) { node = [] }
        if buckets.contains(.ruby) { ruby = [] }
    }

    public func scanners(runner: CommandRunning, options: ScannerOptions = ScannerOptions()) -> [Bucket: any PackageScanner] {
        var scanners: [Bucket: any PackageScanner] = [:]
        if let homebrew {
            scanners[.homebrew] = HomebrewScanner(installation: homebrew, runner: runner, options: options.homebrew)
        }
        if !node.isEmpty {
            scanners[.node] = NodeScanner(installations: node, runner: runner, options: options.node)
        }
        if !ruby.isEmpty {
            scanners[.ruby] = RubyScanner(installations: ruby, runner: runner, options: options.ruby)
        }
        return scanners
    }

    /// Why a bucket cannot be scanned. A bucket that is not listed here is ready, or turned off.
    public var setupProblems: [Bucket: String] {
        var problems: [Bucket: String] = [:]
        if homebrew == nil {
            problems[.homebrew] = chosenPathProblems[.homebrew] ?? String(localized: "Homebrew was not found in /opt/homebrew or /usr/local.", bundle: .module)
        }
        if node.isEmpty {
            problems[.node] = chosenPathProblems[.node] ?? String(localized: "No Node version manager found. DevHub looked for nvm, fnm, Volta and asdf.", bundle: .module)
        }
        if ruby.isEmpty {
            problems[.ruby] = chosenPathProblems[.ruby] ?? String(localized: "No Ruby version manager found. DevHub looked for RVM, rbenv, chruby and asdf.", bundle: .module)
        }
        for bucket in disabled { problems[bucket] = nil }
        return problems
    }
}
