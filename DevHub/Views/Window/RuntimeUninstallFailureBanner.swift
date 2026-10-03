import DevHubCore
import SwiftUI

struct RuntimeUninstallFailureBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let failure = state.runtimeUninstallFailure {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not uninstall \(failure.runtime.bucket.displayName) \(failure.runtime.version)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: failure.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button("Dismiss") { state.dismissRuntimeUninstallFailure() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .clickable()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
}
