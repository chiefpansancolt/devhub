import DevHubCore
import Foundation

let arguments = CommandLine.arguments
let refreshHomebrew = !arguments.contains("--no-update")
let runner = CommandRunner()

var scanners: [any PackageScanner] = []
var notes: [String] = []

if let brew = HomebrewLocator.locate() {
    scanners.append(HomebrewScanner(installation: brew, runner: runner, options: HomebrewOptions(refreshIndexFirst: refreshHomebrew)))
} else {
    notes.append("Homebrew: not found in /opt/homebrew or /usr/local")
}

let node = NodeVersionDiscovery().installations()
if node.isEmpty {
    notes.append("Node: no version manager found (looked for nvm, fnm, Volta and asdf)")
} else {
    scanners.append(NodeScanner(installations: node, runner: runner))
}

let nodeManagers = NodePackageManagerLocator.locate(nodeInstallations: node)
if !nodeManagers.isEmpty {
    scanners.append(NodeToolsScanner(installations: nodeManagers, runner: runner, nodeBinDirectory: node.first?.binDirectory))
}

let ruby = RubyVersionDiscovery().installations()
if ruby.isEmpty {
    notes.append("Ruby: no version manager found (looked for RVM, rbenv, chruby and asdf)")
} else {
    scanners.append(RubyScanner(installations: ruby, runner: runner))
}

if let rust = RustLocator.locate() {
    scanners.append(RustScanner(installation: rust, runner: runner))
} else {
    notes.append("Rust: rustup not found in ~/.cargo/bin or Homebrew")
}

let python = PythonLocator.locate()
if python.isEmpty {
    notes.append("Python: neither pipx nor uv found")
} else {
    scanners.append(PythonScanner(installations: python, runner: runner))
}

for note in notes { print(note) }

for scanner in scanners {
    let started = ContinuousClock.now
    let result = await scanner.scan()
    let elapsed = ContinuousClock.now - started
    let outdated = result.packages.filter(\.isOutdated)

    print("\n\(scanner.bucket.displayName): \(result.packages.count) installed, \(outdated.count) outdated (\(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated))))")
    for issue in result.issues {
        print("  ! \(issue.group.map { "\($0): " } ?? "")\(issue.message)")
    }
    for package in outdated {
        let group = package.group.map { "[\($0)] " } ?? ""
        print("  \(group)\(package.name)  \(package.installedVersion) -> \(package.availableUpdate ?? "")")
    }
}
