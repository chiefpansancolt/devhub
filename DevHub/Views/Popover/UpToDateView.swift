import DevHubCore
import SwiftUI

struct UpToDateView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Everything is up to date")
                    .font(.system(size: 15, weight: .semibold))
                CheckedAgoText(date: state.lastChecked)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)

            ForEach(state.toolsNeedingSetup, id: \.bucket) { tool in
                Divider()
                NotSetUpRow(bucket: tool.bucket, message: tool.reason)
            }
        }
    }
}
