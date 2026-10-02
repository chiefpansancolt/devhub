import DevHubCore
import SwiftUI

extension Bucket {
    var settingsTab: SettingsTab {
        switch self {
        case .homebrew: .homebrew
        case .node: .node
        case .ruby: .ruby
        case .rust: .rust
        case .python: .python
        }
    }

    var logo: String {
        switch self {
        case .homebrew: "BucketHomebrew"
        case .node: "BucketNode"
        case .ruby: "BucketRuby"
        case .rust: "BucketRust"
        case .python: "BucketPython"
        }
    }
}

struct BucketBadge: View {
    let bucket: Bucket
    var size: CGFloat = 28

    var body: some View {
        Image(bucket.logo)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

extension SettingsTab {
    var bucket: Bucket? {
        switch self {
        case .homebrew: .homebrew
        case .node: .node
        case .ruby: .ruby
        case .rust: .rust
        case .python: .python
        case .general, .appearance, .history: nil
        }
    }
}

extension Bucket {
    var groupsByVersion: Bool {
        self == .node || self == .ruby
    }
}

extension PackageKind {
    var singularTitle: LocalizedStringKey {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        case .npmGlobal: "npm global"
        case .gem: "Gem"
        case .rustToolchain: "Toolchain"
        case .cargoTool: "Cargo tool"
        case .pythonTool: "Python tool"
        case .pnpmGlobal: "pnpm global"
        case .bunGlobal: "Bun global"
        case .yarnGlobal: "Yarn global"
        }
    }

    var pluralTitle: LocalizedStringKey {
        switch self {
        case .formula: "Formulae"
        case .cask: "Casks"
        case .rustToolchain: "Toolchains"
        case .cargoTool: "Cargo tools"
        case .npmGlobal, .gem, .pythonTool, .pnpmGlobal, .bunGlobal, .yarnGlobal: singularTitle
        }
    }
}
