import AppKit
import DevHubCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var opensAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?
    @State private var notificationAccess = NotificationAuthorization.notAsked
    private let notifier = SystemNotifier()

    var body: some View {
        @Bindable var settings = settings
        let installed = Toolchain.detect(settings: settings.values, includingDisabledTools: true)
        Form {
            Section {
                ForEach(Bucket.allCases, id: \.self) { bucket in
                    Toggle(isOn: isOn(bucket)) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bucket.displayName)
                                Text(isInstalled(bucket, in: installed) ? "Found on this Mac" : "Not found on this Mac")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            BucketBadge(bucket: bucket, size: 20)
                        }
                    }
                    .clickable()
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Turn off a tool you do not use. DevHub stops checking it and hides it from the menu bar, the window sidebar and these Settings.")
            }

            Section("Update checks") {
                Picker("Check for updates", selection: $settings.values.checkInterval) {
                    Text("Every hour").tag(CheckInterval.hourly)
                    Text("Every 4 hours").tag(CheckInterval.everyFourHours)
                    Text("Once a day").tag(CheckInterval.daily)
                    Text("Manually only").tag(CheckInterval.manual)
                }
                .clickable()
                Toggle("Check when DevHub opens", isOn: $settings.values.checkOnLaunch)
                .clickable()
                Toggle("Check when the Mac wakes from sleep", isOn: $settings.values.checkOnWake)
                .clickable()
                LabeledContent("Last checked") {
                    HStack(spacing: 10) {
                        if state.hasChecked {
                            CheckedAgoText(date: state.lastChecked).foregroundStyle(.secondary)
                        }
                        Button("Check now") { state.startRefresh() }
                            .clickable()
                            .disabled(state.isChecking || state.isBusy)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Notify me about new updates", isOn: notificationsAreOn)
                    .clickable()
                Picker("Notify", selection: $settings.values.notificationFrequency) {
                    Text("For every update").tag(NotificationFrequency.everyUpdate)
                    Text("Once a day, as a summary").tag(NotificationFrequency.dailySummary)
                    Text("Only for major versions").tag(NotificationFrequency.majorVersionsOnly)
                }
                .clickable()
                .disabled(!settings.values.notifyAboutUpdates)
                Toggle("Play a sound", isOn: $settings.values.notificationSound)
                    .clickable()
                    .disabled(!settings.values.notifyAboutUpdates)
                if notificationAccess == .denied {
                    HStack {
                        Label("Notifications are turned off for DevHub in System Settings.", systemImage: "exclamationmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Open System Settings") { openNotificationSettings() }
                            .clickable()
                    }
                }
                LabeledContent("Try it") {
                    Button("Send a test notification") { sendTestNotification() }
                        .clickable()
                }
            }

            Section("Startup") {
                Toggle("Open DevHub at login", isOn: Binding(get: { opensAtLogin }, set: { setLoginItem($0) }))
                .clickable()
                if let loginError {
                    Text(loginError).font(.system(size: 12)).foregroundStyle(.red)
                }
                if loginNeedsApproval {
                    HStack {
                        Text("Allow DevHub in System Settings, under Login Items.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") { LoginItem.openSystemSettings() }
                            .clickable()
                    }
                }
            }

            Section("Window") {
                Toggle("Show the command output log", isOn: $settings.values.showOutputLog)
                .clickable()
            }

            Section("Safety") {
                Toggle("Ask before uninstalling", isOn: $settings.values.confirmUninstall)
                .clickable()
                Toggle("Ask before Update all", isOn: $settings.values.confirmUpdateAll)
                .clickable()
            }
        }
        .formStyle(.grouped)
        .task { notificationAccess = await notifier.authorization() }
    }

    // The first time it is turned on, macOS asks for permission.
    private var notificationsAreOn: Binding<Bool> {
        Binding(
            get: { settings.values.notifyAboutUpdates },
            set: { isOn in
                settings.values.notifyAboutUpdates = isOn
                guard isOn else { return }
                Task {
                    _ = await notifier.requestAuthorization()
                    notificationAccess = await notifier.authorization()
                }
            }
        )
    }

    private func sendTestNotification() {
        let test = UpdateNotification(title: String(localized: "DevHub test notification"), body: String(localized: "If you can read this, notifications work."))
        Task {
            await notifier.send(test, playSound: settings.values.notificationSound)
            notificationAccess = await notifier.authorization()
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func isOn(_ bucket: Bucket) -> Binding<Bool> {
        Binding(
            get: { !settings.values.disabledBuckets.contains(bucket) },
            set: { isOn in
                if isOn { settings.values.disabledBuckets.remove(bucket) } else { settings.values.disabledBuckets.insert(bucket) }
            }
        )
    }

    private func isInstalled(_ bucket: Bucket, in toolchain: Toolchain) -> Bool {
        switch bucket {
        case .homebrew: toolchain.homebrew != nil
        case .node: !toolchain.node.isEmpty
        case .ruby: !toolchain.ruby.isEmpty
        case .rust: toolchain.rust != nil
        }
    }

    private func refreshLoginItem() {
        loginNeedsApproval = LoginItem.needsApproval
        opensAtLogin = LoginItem.isEnabled || loginNeedsApproval
    }

    private func setLoginItem(_ enabled: Bool) {
        loginError = LoginItem.set(enabled)
        refreshLoginItem()
    }
}
