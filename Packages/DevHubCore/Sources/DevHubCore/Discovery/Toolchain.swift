/// The package managers found on this Mac.
public struct Toolchain: Sendable {
    public var homebrew: HomebrewInstallation?
    public var node: [NodeInstallation]
    public var ruby: [RubyInstallation]

    public init(homebrew: HomebrewInstallation?, node: [NodeInstallation], ruby: [RubyInstallation]) {
        self.homebrew = homebrew
        self.node = node
        self.ruby = ruby
    }

    public static func detect() -> Toolchain {
        Toolchain(
            homebrew: HomebrewLocator.locate(),
            node: NodeVersionDiscovery().installations(),
            ruby: RubyVersionDiscovery().installations()
        )
    }

    public func scanners(runner: CommandRunning, homebrew options: HomebrewOptions = HomebrewOptions()) -> [Bucket: any PackageScanner] {
        var scanners: [Bucket: any PackageScanner] = [:]
        if let homebrew {
            scanners[.homebrew] = HomebrewScanner(installation: homebrew, runner: runner, options: options)
        }
        if !node.isEmpty {
            scanners[.node] = NodeScanner(installations: node, runner: runner)
        }
        if !ruby.isEmpty {
            scanners[.ruby] = RubyScanner(installations: ruby, runner: runner)
        }
        return scanners
    }

    /// Why a bucket cannot be scanned. A bucket that is not listed here is ready.
    public var setupProblems: [Bucket: String] {
        var problems: [Bucket: String] = [:]
        if homebrew == nil {
            problems[.homebrew] = "Homebrew was not found in /opt/homebrew or /usr/local."
        }
        if node.isEmpty {
            problems[.node] = "No Node version manager found. DevHub looked for nvm, fnm, Volta and asdf."
        }
        if ruby.isEmpty {
            problems[.ruby] = "No Ruby version manager found. DevHub looked for RVM, rbenv, chruby and asdf."
        }
        return problems
    }
}
