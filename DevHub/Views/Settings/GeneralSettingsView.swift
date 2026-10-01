import DevHubCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

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

            Section("Checking") {
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

            Section("Startup") {
                Toggle("Open DevHub at login", isOn: Binding(get: { opensAtLogin }, set: setLoginItem))
                .clickable()
                if let loginError {
                    Text(loginError).font(.system(size: 12)).foregroundStyle(.red)
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
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        loginError = LoginItem.set(enabled)
        opensAtLogin = LoginItem.isEnabled
    }
}
