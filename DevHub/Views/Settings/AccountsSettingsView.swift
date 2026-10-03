import AppKit
import DevHubCore
import SwiftUI

struct AccountsSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingDisconnect = false

    var body: some View {
        @Bindable var settings = settings
        let login = state.syncAccountLogin
        Form {
            if state.signIn != .idle {
                SignInSection()
            } else if let login {
                AccountSection(login: login) { isConfirmingDisconnect = true }
            } else {
                ConnectSection()
            }

            if let login {
                SyncSection(login: login, automatically: $settings.values.syncStandardPackagesAutomatically)
            } else if state.signIn == .idle {
                PermissionSection()
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isConfirmingDisconnect) {
            DisconnectSheet { Task { await state.disconnectGitHub() } }
        }
    }
}

private struct GitHubMark: View {
    let size: CGFloat

    var body: some View {
        Image("GitHubMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct Chip: View {
    let text: Text
    let color: Color

    var body: some View {
        text
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: Not connected

private struct ConnectSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section {
            HStack(spacing: 12) {
                GitHubMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub").fontWeight(.semibold)
                    Text("Keep your standard packages lists the same on every Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Connect GitHub") { state.connectGitHub() }
                    .buttonStyle(.borderedProminent)
                    .clickable()
            }
        } header: {
            Text("GitHub")
        }
    }
}

private struct PermissionSection: View {
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DevHub asks GitHub for the `repo` permission, because that is the only way to create a private repository. It can read and write all of your private repositories. DevHub only uses it for one repository, `devhub-standard-packages`. You can revoke it at any time on GitHub.")
                    Link(destination: GitHubSync.applicationsURL) { Text(verbatim: "github.com/settings/applications") }
                        .clickable()
                }
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            }
            Label {
                Text("Only the names in your standard packages lists are uploaded. Installed packages are never uploaded, and a sync never installs anything.")
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
            }
        } header: {
            Text("What this connection can do")
        }
    }
}

// MARK: Signing in

private struct SignInSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section {
            HStack(spacing: 12) {
                GitHubMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect GitHub").fontWeight(.semibold)
                    Text("Open `github.com/login/device` and enter this code.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            switch state.signIn {
            case .idle:
                EmptyView()
            case .requesting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Contacting GitHub…").foregroundStyle(.secondary)
                    Spacer()
                    cancel
                }
            case let .waiting(code):
                waiting(code)
            case let .failed(message):
                failed(message)
            }
        }
    }

    private var cancel: some View {
        Button("Cancel") { state.cancelSignIn() }
            .buttonStyle(.borderless)
            .clickable()
    }

    @ViewBuilder
    private func waiting(_ code: DeviceCodeInfo) -> some View {
        Text(verbatim: code.userCode)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .kerning(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        HStack(spacing: 10) {
            Spacer()
            Button("Copy code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
            }
            .clickable()
            Button("Open GitHub") { NSWorkspace.shared.open(code.verificationURL) }
                .buttonStyle(.borderedProminent)
                .clickable()
            cancel
            Spacer()
        }
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for you to approve in the browser…")
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
                Text("The code expires in \(String(format: "%d:%02d", remaining / 60, remaining % 60)).")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Label {
            Text(verbatim: message).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        HStack(spacing: 10) {
            Spacer()
            Button("Try again") {
                state.dismissSignInFailure()
                state.connectGitHub()
            }
            .buttonStyle(.borderedProminent)
            .clickable()
            Button("Cancel") { state.dismissSignInFailure() }
                .buttonStyle(.borderless)
                .clickable()
        }
    }
}

// MARK: Connected

private struct AccountSection: View {
    let login: String
    let disconnect: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 12) {
                GitHubMark(size: 20)
                    .frame(width: 34, height: 34)
                    .background(.quaternary, in: Circle())
                Text(verbatim: login).fontWeight(.semibold)
                Chip(text: Text("Connected"), color: .green)
                Spacer(minLength: 8)
                Button("Disconnect", role: .destructive, action: disconnect)
                    .clickable()
            }
        } header: {
            Text("GitHub")
        }
    }
}

private struct SyncSection: View {
    @Environment(AppState.self) private var state
    let login: String
    @Binding var automatically: Bool

    var body: some View {
        Section {
            Toggle(isOn: $automatically) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync automatically")
                    Text("Checks GitHub when DevHub opens and after each check, and uploads a few seconds after you change a list.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .clickable()
            LabeledContent {
                Button("Open on GitHub") { NSWorkspace.shared.open(GitHubRepoClient.repositoryURL(login: login)) }
                    .clickable()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Repository")
                    HStack(spacing: 8) {
                        Text(verbatim: "\(login)/\(GitHubRepoClient.repositoryName)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Chip(text: Text("Private"), color: .secondary)
                    }
                }
            }
            SyncStatusRow()
        } header: {
            Text("Standard packages sync")
        } footer: {
            Text("A sync only changes your lists. Nothing is installed until you choose Install.")
        }
    }
}

// MARK: Status

private enum StatusAction {
    case syncNow
    case tryAgain
    case connectAgain
}

private struct SyncStatusDisplay {
    let symbol: String
    let tint: Color
    let title: Text
    let detail: Text
    let action: StatusAction
    let isBusy: Bool
}

private struct SyncStatusRow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let display = display(at: context.date)
            HStack(alignment: .top, spacing: 10) {
                icon(display)
                VStack(alignment: .leading, spacing: 2) {
                    display.title.fontWeight(.semibold)
                    display.detail
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                actionButton(display)
            }
        }
    }

    @ViewBuilder
    private func icon(_ display: SyncStatusDisplay) -> some View {
        if display.isBusy {
            ProgressView().controlSize(.small).frame(width: 16)
        } else {
            Image(systemName: display.symbol)
                .foregroundStyle(display.tint)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func actionButton(_ display: SyncStatusDisplay) -> some View {
        switch display.action {
        case .syncNow:
            Button("Sync now") { state.syncNow() }
                .disabled(display.isBusy)
                .clickable()
        case .tryAgain:
            Button("Try again") { state.syncNow() }
                .clickable()
        case .connectAgain:
            Button("Connect again") { state.connectGitHub() }
                .buttonStyle(.borderedProminent)
                .clickable()
        }
    }

    private func display(at now: Date) -> SyncStatusDisplay {
        if state.isSyncing {
            return SyncStatusDisplay(
                symbol: "arrow.triangle.2.circlepath", tint: .accentColor, title: Text("Syncing…"),
                detail: Text("Checking GitHub for changes."), action: .syncNow, isBusy: true
            )
        }
        guard let result = state.syncResult else {
            return SyncStatusDisplay(
                symbol: "clock", tint: .secondary, title: Text("Not synced yet"),
                detail: Text("Choose Sync now to upload and download your lists."), action: .syncNow, isBusy: false
            )
        }
        if let failure = result.failure {
            return failureDisplay(failure, lastSuccess: state.syncLastSuccessAt, now: now)
        }
        return SyncStatusDisplay(
            symbol: "checkmark.circle", tint: .green, title: Text("Last synced \(SyncTime.text(result.at, now: now))"),
            detail: SyncTime.summary(result.summary), action: .syncNow, isBusy: false
        )
    }

    private func failureDisplay(_ failure: SyncFailure, lastSuccess: Date?, now: Date) -> SyncStatusDisplay {
        switch failure.kind {
        case .offline:
            let detail = lastSuccess.map { Text("Last synced \(SyncTime.text($0, now: now)). DevHub tries again at the next check.") }
                ?? Text("DevHub tries again at the next check.")
            return SyncStatusDisplay(symbol: "exclamationmark.triangle.fill", tint: .orange, title: Text("Could not reach GitHub"), detail: detail, action: .tryAgain, isBusy: false)
        case .unauthorized:
            return SyncStatusDisplay(
                symbol: "exclamationmark.circle.fill", tint: .red, title: Text("GitHub no longer accepts this sign-in"),
                detail: Text("The access may have been revoked. Connect again to keep syncing."), action: .connectAgain, isBusy: false
            )
        case .newerFile:
            return SyncStatusDisplay(
                symbol: "exclamationmark.triangle.fill", tint: .orange, title: Text("The file on GitHub is from a newer DevHub"),
                detail: Text("Nothing was uploaded, so nothing was overwritten. Update DevHub to sync again."), action: .tryAgain, isBusy: false
            )
        case .refused:
            return SyncStatusDisplay(
                symbol: "exclamationmark.triangle.fill", tint: .orange, title: Text("GitHub refused the request"),
                detail: Text("GitHub is limiting requests, or your organization blocks this app. DevHub tries again at the next check."), action: .tryAgain, isBusy: false
            )
        case .other:
            return SyncStatusDisplay(
                symbol: "exclamationmark.triangle.fill", tint: .orange, title: Text("The last sync failed"),
                detail: Text(verbatim: failure.message), action: .tryAgain, isBusy: false
            )
        }
    }
}

private enum SyncTime {
    static func text(_ date: Date, now: Date) -> Text {
        now.timeIntervalSince(date) < 60
            ? Text("just now")
            : Text(date, format: .relative(presentation: .numeric, unitsStyle: .wide))
    }

    static func summary(_ summary: SyncSummary?) -> Text {
        guard let summary, !summary.isEmpty else { return Text("No changes") }
        let added = summary.added > 0 ? Text("\(summary.added) names added") : nil
        let removed = summary.removed > 0 ? Text("\(summary.removed) names removed") : nil
        return [added, removed].compactMap { $0 }.reduce(nil as Text?) { joined, part in
            joined.map { $0 + Text(verbatim: ", ") + part } ?? part
        } ?? Text("No changes")
    }
}

// MARK: Disconnecting

private struct DisconnectSheet: View {
    let disconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Disconnect GitHub?").font(.title3.weight(.semibold))
            Text("DevHub stops syncing and forgets the sign-in on this Mac. Your lists stay as they are, and the repository stays on GitHub. To remove the access completely, revoke it on GitHub.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Revoke on GitHub", destination: GitHubSync.applicationsURL)
                .clickable()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .clickable()
                Button("Disconnect", role: .destructive) {
                    disconnect()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .clickable()
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
