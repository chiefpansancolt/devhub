import DevHubCore
import SwiftUI

struct NoToolsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "switch.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("All tools are turned off").font(.system(size: 15, weight: .semibold))
            Text("Turn on Homebrew, Node or Ruby in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                settings.selectedTab = .general
                openSettings()
                AppActivation.bringToFront()
            }
            .controlSize(.regular)
            .clickable()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }
}
