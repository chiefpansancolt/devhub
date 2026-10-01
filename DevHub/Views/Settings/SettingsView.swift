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
            HomebrewSettingsView()
                .tabItem { Label("Homebrew", systemImage: "mug") }
                .tag(SettingsTab.homebrew)
            NodeSettingsView()
                .tabItem { Label("Node", systemImage: "hexagon") }
                .tag(SettingsTab.node)
            RubySettingsView()
                .tabItem { Label("Ruby", systemImage: "diamond") }
                .tag(SettingsTab.ruby)
            HistorySettingsView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(width: 600, height: 560)
        .onAppear { AppActivation.windowOpened() }
        .onDisappear { AppActivation.windowClosed() }
    }
}
