import Foundation

public enum RemoteFileProblem: Equatable, Sendable {
    case newerVersion(Int)
    case hasUnreadableEntries(Int)
    case notOurFile
    case unreadable
    case tooLarge
}

public enum SyncFailureKind: String, Codable, Sendable {
    case offline
    case unauthorized
    case refused
    case newerFile
    case other
}

public enum SyncError: Error, Equatable, Sendable {
    case offline(String)
    case unauthorized
    case forbidden(String)
    case server(Int)
    case conflict
    case unexpectedResponse
    case deviceFlowDisabled
    case accessDenied
    case codeExpired
    case keychain(String)
    case remoteFileNotUsable(RemoteFileProblem)
    case tooManyConflicts
    case repositoryNotReady

    public var kind: SyncFailureKind {
        switch self {
        case .offline: .offline
        case .unauthorized: .unauthorized
        case .forbidden: .refused
        case .remoteFileNotUsable(.newerVersion), .remoteFileNotUsable(.hasUnreadableEntries): .newerFile
        default: .other
        }
    }
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Could not reach GitHub.", bundle: .module)
        case .unauthorized: String(localized: "GitHub no longer accepts this sign-in. Connect again to keep syncing.", bundle: .module)
        case let .forbidden(message): String(localized: "GitHub refused the request: \(message)", bundle: .module)
        case let .server(status): String(localized: "GitHub answered with an error (\(status)).", bundle: .module)
        case .conflict: String(localized: "The file changed on GitHub during the sync.", bundle: .module)
        case .unexpectedResponse: String(localized: "GitHub sent an answer that DevHub could not read.", bundle: .module)
        case .deviceFlowDisabled: String(localized: "Device sign-in is turned off for the DevHub app on GitHub.", bundle: .module)
        case .accessDenied: String(localized: "The sign-in was cancelled on GitHub.", bundle: .module)
        case .codeExpired: String(localized: "The code expired. Start again.", bundle: .module)
        case let .keychain(detail): String(localized: "DevHub could not use the keychain: \(detail)", bundle: .module)
        case .tooManyConflicts: String(localized: "The file kept changing on GitHub. DevHub tries again at the next sync.", bundle: .module)
        case .repositoryNotReady: String(localized: "GitHub has not finished creating the repository. DevHub tries again at the next sync.", bundle: .module)
        case .remoteFileNotUsable(.newerVersion), .remoteFileNotUsable(.hasUnreadableEntries):
            String(localized: "The file on GitHub was written by a newer version of DevHub. Update DevHub to sync again. Nothing was uploaded.", bundle: .module)
        case .remoteFileNotUsable(.notOurFile):
            String(localized: "The file in the repository is not a DevHub standard packages file. Nothing was uploaded.", bundle: .module)
        case .remoteFileNotUsable(.unreadable):
            String(localized: "The file in the repository could not be read. Nothing was uploaded.", bundle: .module)
        case .remoteFileNotUsable(.tooLarge):
            String(localized: "The file in the repository is too large to read. Nothing was uploaded.", bundle: .module)
        }
    }

    /// The text for the output log, which keeps what the message leaves out.
    public var logDetail: String {
        switch self {
        case let .offline(detail), let .keychain(detail): detail
        default: errorDescription ?? ""
        }
    }
}
