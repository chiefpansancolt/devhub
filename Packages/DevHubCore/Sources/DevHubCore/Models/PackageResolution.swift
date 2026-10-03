/// What installing a package would do, found without installing it.
public enum PackageResolution: Sendable, Equatable {
    /// The newest version installs.
    case current(version: String)
    /// The newest version does not support this runtime, so an older one installs.
    case older(newest: String, installs: String)
    /// No version supports this runtime.
    case incompatible(newest: String)
    case notFound
    /// The lookup could not finish. `reason` is one line for the person, and `details` holds what the tool printed.
    case unavailable(reason: String, details: String?)

    public var installVersion: String? {
        switch self {
        case let .current(version): version
        case let .older(_, installs): installs
        case .incompatible, .notFound, .unavailable: nil
        }
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { true } else { false }
    }
}

extension PackageResolution {
    private static let detailLines = 6
    private static let detailLength = 600

    /// A tool that ran and failed. The first line it printed is the reason and the first lines together are the details.
    static func commandFailed(_ tool: String, _ result: CommandResult) -> PackageResolution {
        let printed = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let lines = printed.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isStackFrame($0) }
        guard let first = lines.first else {
            return .unavailable(reason: String(localized: "\(tool) exited with code \(result.exitCode).", bundle: .module), details: nil)
        }
        let details = String(lines.prefix(detailLines).joined(separator: "\n").prefix(detailLength))
        return .unavailable(reason: String(localized: "\(tool) failed: \(first)", bundle: .module), details: details)
    }

    // A stack trace buries the line that explains the failure, such as `at ClientRequest.emit (node:events:514:28)`.
    private static func isStackFrame(_ line: String) -> Bool {
        line.range(of: #"\bat\s+\S.*:\d+:\d+\)?$"#, options: .regularExpression) != nil
    }

    static func couldNotRun(_ tool: String, detail: String) -> PackageResolution {
        .unavailable(reason: String(localized: "Could not run \(tool): \(detail)", bundle: .module), details: nil)
    }

    static func unreadable(_ tool: String, _ result: CommandResult) -> PackageResolution {
        let lines = result.standardOutput.split(whereSeparator: \.isNewline).prefix(detailLines).joined(separator: "\n")
        return .unavailable(reason: String(localized: "\(tool) printed output that DevHub could not read.", bundle: .module), details: lines.isEmpty ? nil : String(lines.prefix(detailLength)))
    }
}
