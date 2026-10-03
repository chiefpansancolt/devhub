import DevHubCore
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        TabView(selection: $settings.selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsTab.appearance)
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            if isOn(.homebrew) {
                HomebrewSettingsView()
                    .tabItem { Label { Text("Homebrew") } icon: { Image("TabHomebrew") } }
                    .tag(SettingsTab.homebrew)
            }
            if isOn(.node) {
                NodeSettingsView()
                    .tabItem { Label { Text("Node") } icon: { Image("TabNode") } }
                    .tag(SettingsTab.node)
            }
            if isOn(.ruby) {
                RubySettingsView()
                    .tabItem { Label { Text("Ruby") } icon: { Image("TabRuby") } }
                    .tag(SettingsTab.ruby)
            }
            if isOn(.rust) {
                RustSettingsView()
                    .tabItem { Label { Text("Rust") } icon: { Image("TabRust") } }
                    .tag(SettingsTab.rust)
            }
            if isOn(.python) {
                PythonSettingsView()
                    .tabItem { Label { Text("Python") } icon: { Image("TabPython") } }
                    .tag(SettingsTab.python)
            }
            HistorySettingsView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(width: 700, height: 560)
        .onAppear { AppActivation.windowOpened() }
        .onDisappear { AppActivation.windowClosed() }
        .onChange(of: settings.values.disabledBuckets) {
            if let bucket = settings.selectedTab.bucket, !isOn(bucket) {
                settings.selectedTab = .general
            }
        }
    }

    private func isOn(_ bucket: Bucket) -> Bool {
        !settings.values.disabledBuckets.contains(bucket)
    }
}
