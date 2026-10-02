import DevHubCore
import SwiftUI

struct UpdateProgressStrip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let session = state.session, session.isRunning {
            strip {
                ProgressView(value: Double(session.finishedCount), total: Double(session.items.count))
                    .frame(width: 120)
                Text("Updating").foregroundStyle(.secondary)
                if let item = session.runningItem {
                    Text(verbatim: runningName(item.package)).fontWeight(.semibold).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(session.finishedCount) of \(session.items.count)").foregroundStyle(.secondary).monospacedDigit()
                elapsed
                Button("Cancel") { state.cancelUpdate() }
                    .controlSize(.small)
                    .clickable()
            }
        } else if state.uninstallProgress?.status == .updating {
            strip {
                ProgressView().controlSize(.small)
                Text("Removing").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                elapsed
            }
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if let since = state.runningSince {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func runningName(_ package: InstalledPackage) -> String {
        package.group.map { "\(package.name) · \($0)" } ?? package.name
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10, content: content)
                .font(.system(size: 12))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
