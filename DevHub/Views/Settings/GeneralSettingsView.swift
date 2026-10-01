import DevHubCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
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

    private func setLoginItem(_ enabled: Bool) {
        loginError = LoginItem.set(enabled)
        opensAtLogin = LoginItem.isEnabled
    }
}
