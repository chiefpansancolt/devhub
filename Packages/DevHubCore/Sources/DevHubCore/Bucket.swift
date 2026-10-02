public enum Bucket: String, CaseIterable, Sendable, Codable {
    case homebrew
    case node
    case ruby
    case rust
    case python

    public var displayName: String {
        switch self {
        case .homebrew: "Homebrew"
        case .node: "Node"
        case .ruby: "Ruby"
        case .rust: "Rust"
        case .python: "Python"
        }
    }
}
