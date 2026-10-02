import Foundation

public struct ScannerOptions: Sendable, Equatable {
    public var homebrew = HomebrewOptions()
    public var node = NodeOptions()
    public var ruby = RubyOptions()
    public var rust = RustOptions()

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
        rust = RustOptions(includeCargoTools: settings.rustIncludeCargoTools)
    }
}

public struct Toolchain: Sendable {
    public var homebrew: HomebrewInstallation?
    public var node: [NodeInstallation]
    public var nodeManagers: [NodePackageManagerInstallation]
    public var ruby: [RubyInstallation]
    public var rust: RustInstallation?
    public var python: [PythonInstallation]
    private var chosenPathProblems: [Bucket: String]
    public private(set) var disabled: Set<Bucket>

    public init(
        homebrew: HomebrewInstallation?,
        node: [NodeInstallation],
        nodeManagers: [NodePackageManagerInstallation] = [],
        ruby: [RubyInstallation],
        rust: RustInstallation? = nil,
        python: [PythonInstallation] = [],
        chosenPathProblems: [Bucket: String] = [:],
        disabled: Set<Bucket> = []
    ) {
        self.homebrew = homebrew
        self.node = node
        self.nodeManagers = nodeManagers
        self.ruby = ruby
        self.rust = rust
        self.python = python
        self.chosenPathProblems = chosenPathProblems
        self.disabled = disabled
    }

    public static func detect() -> Toolchain {
        detect(settings: SettingsValues())
    }

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

        var nodeManagers = NodePackageManagerLocator.locate(nodeInstallations: node)
        for (manager, path) in [(NodePackageManager.pnpm, settings.pnpmPath), (.bun, settings.bunPath), (.yarn, settings.yarnPath)] {
            guard let path else { continue }
            nodeManagers.removeAll { $0.manager == manager }
            if FileManager.default.isExecutableFile(atPath: path) {
                nodeManagers.append(NodePackageManagerInstallation(manager: manager, executable: URL(filePath: path)))
            } else {
                problems[.node] = String(localized: "There is no \(manager.displayName) program at \(path).", bundle: .module)
            }
        }
        if applyingExclusions {
            nodeManagers.removeAll { settings.excludedNodeManagers.contains($0.manager.rawValue) }
        }

        var ruby = RubyVersionDiscovery(versionsFolder: settings.rubyFolder.map { URL(filePath: $0) }).installations()
        if let path = settings.rubyFolder, ruby.isEmpty {
            problems[.ruby] = String(localized: "No Ruby versions were found in \(path).", bundle: .module)
        }
        if applyingExclusions, !ruby.isEmpty {
            ruby.removeAll { settings.excludedRubyVersions.contains($0.version) }
            if ruby.isEmpty { problems[.ruby] = String(localized: "Every Ruby version is turned off in Settings.", bundle: .module) }
        }

        var rust = RustLocator.locate()
        if let path = settings.rustPath {
            if FileManager.default.isExecutableFile(atPath: path) {
                rust = RustLocator.installation(rustup: URL(filePath: path))
            } else {
                rust = nil
                problems[.rust] = String(localized: "There is no rustup program at \(path).", bundle: .module)
            }
        }

        var python = PythonLocator.locate()
        for (manager, path) in [(PythonManager.pipx, settings.pipxPath), (.uv, settings.uvPath)] {
            guard let path else { continue }
            python.removeAll { $0.manager == manager }
            if FileManager.default.isExecutableFile(atPath: path) {
                python.append(PythonInstallation(manager: manager, executable: URL(filePath: path)))
            } else {
                problems[.python] = String(localized: "There is no \(manager.rawValue) program at \(path).", bundle: .module)
            }
        }
        python.sort { $0.manager.rawValue < $1.manager.rawValue }
        if applyingExclusions, !python.isEmpty {
            python.removeAll { settings.excludedPythonManagers.contains($0.manager.rawValue) }
            if python.isEmpty { problems[.python] = String(localized: "Every Python tool manager is turned off in Settings.", bundle: .module) }
        }

        var toolchain = Toolchain(homebrew: homebrew, node: node, nodeManagers: nodeManagers, ruby: ruby, rust: rust, python: python, chosenPathProblems: problems)
        if !includingDisabledTools {
            toolchain.turnOff(settings.disabledBuckets)
        }
        return toolchain
    }

    private mutating func turnOff(_ buckets: Set<Bucket>) {
        disabled = buckets
        if buckets.contains(.homebrew) { homebrew = nil }
        if buckets.contains(.node) {
            node = []
            nodeManagers = []
        }
        if buckets.contains(.ruby) { ruby = [] }
        if buckets.contains(.rust) { rust = nil }
        if buckets.contains(.python) { python = [] }
    }

    public func scanners(runner: CommandRunning, options: ScannerOptions = ScannerOptions()) -> [Bucket: any PackageScanner] {
        var scanners: [Bucket: any PackageScanner] = [:]
        if let homebrew {
            scanners[.homebrew] = HomebrewScanner(installation: homebrew, runner: runner, options: options.homebrew)
        }
        var nodeScanners: [any PackageScanner] = []
        if !node.isEmpty {
            nodeScanners.append(NodeScanner(installations: node, runner: runner, options: options.node))
        }
        if !nodeManagers.isEmpty {
            nodeScanners.append(NodeToolsScanner(installations: nodeManagers, runner: runner, nodeBinDirectory: node.first?.binDirectory))
        }
        if nodeScanners.count == 1 {
            scanners[.node] = nodeScanners[0]
        } else if !nodeScanners.isEmpty {
            scanners[.node] = CombinedScanner(bucket: .node, scanners: nodeScanners)
        }
        if !ruby.isEmpty {
            scanners[.ruby] = RubyScanner(installations: ruby, runner: runner, options: options.ruby)
        }
        if let rust {
            scanners[.rust] = RustScanner(installation: rust, runner: runner, options: options.rust)
        }
        if !python.isEmpty {
            scanners[.python] = PythonScanner(installations: python, runner: runner)
        }
        return scanners
    }

    public var knownGroups: [Bucket: [String]] {
        [
            .node: node.map(\.version) + nodeManagers.map(\.manager.displayName),
            .ruby: ruby.map(\.version),
            .python: python.map(\.manager.rawValue)
        ]
    }

    public var setupProblems: [Bucket: String] {
        var problems: [Bucket: String] = [:]
        if homebrew == nil {
            problems[.homebrew] = chosenPathProblems[.homebrew] ?? String(localized: "Homebrew was not found in /opt/homebrew or /usr/local.", bundle: .module)
        }
        if node.isEmpty, nodeManagers.isEmpty {
            problems[.node] = chosenPathProblems[.node] ?? String(localized: "No Node version manager found. DevHub looked for nvm, fnm, Volta and asdf.", bundle: .module)
        }
        if ruby.isEmpty {
            problems[.ruby] = chosenPathProblems[.ruby] ?? String(localized: "No Ruby version manager found. DevHub looked for RVM, rbenv, chruby and asdf.", bundle: .module)
        }
        if rust == nil {
            problems[.rust] = chosenPathProblems[.rust] ?? String(localized: "Rust was not found. DevHub looked for rustup in ~/.cargo/bin and in Homebrew.", bundle: .module)
        }
        if python.isEmpty {
            problems[.python] = chosenPathProblems[.python] ?? String(localized: "No Python tool manager found. DevHub looked for pipx and uv.", bundle: .module)
        }
        for bucket in disabled { problems[bucket] = nil }
        return problems
    }
}
