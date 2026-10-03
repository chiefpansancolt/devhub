import Foundation

enum GitHubSync {
    /// The client ID of the DevHub OAuth app on GitHub. It is public, and the device flow needs no client secret.
    static let clientID = "Ov23likvTlmVx9smsWN3"
    static let applicationsURL = URL(string: "https://github.com/settings/applications")!
}
