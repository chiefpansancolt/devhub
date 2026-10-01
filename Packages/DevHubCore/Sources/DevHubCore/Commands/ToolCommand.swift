import Foundation

public struct ToolCommand: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let context: String?

    public init(executable: URL, arguments: [String], environment: [String: String], context: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.context = context
    }

    public var displayText: String {
        let text = ([executable.lastPathComponent] + arguments).joined(separator: " ")
        guard let context else { return text }
        return "\(text)  (\(context))"
    }
}

public enum ToolEnvironment {
    private static let systemSearchPath = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ]

    // A menu bar app does not inherit the shell environment, so every command gets an explicit one.
    public static func make(
        searchPath: [URL] = [],
        extra: [String: String] = [:],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        let path = (searchPath.map(\.path) + systemSearchPath).joined(separator: ":")
        var environment = [
            "HOME": home.path,
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
            "TERM": "dumb",
            "NO_COLOR": "1",
            "PATH": path
        ]
        environment.merge(extra) { _, new in new }
        return environment
    }
}
