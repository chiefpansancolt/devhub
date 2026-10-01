import DevHubCore
import SwiftUI

struct HistorySettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        let history = state.history

        Form {
            Section("Log file") {
                LabeledContent("History file") {
                    Text(history.fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("One line per action, in JSON Lines format. Each line has a timestamp.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Show in Finder") { HistoryFileActions.showInFinder(history) }
                        .clickable()
                    Button("Export…") { HistoryFileActions.export(history) }
                        .disabled(history.totalCount == 0)
                        .clickable()
                }
            }

            Section("What to keep") {
                Picker("Keep history for", selection: $settings.values.historyRetention) {
                    Text("30 days").tag(HistoryRetention.thirtyDays)
                    Text("90 days").tag(HistoryRetention.ninetyDays)
                    Text("1 year").tag(HistoryRetention.oneYear)
                    Text("Forever").tag(HistoryRetention.forever)
                }
                Picker("Detail level", selection: $settings.values.historyIncludesOutput) {
                    Text("Actions only").tag(false)
                    Text("Actions and command output").tag(true)
                }
                Text("Command output makes the file larger but helps when something fails.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Entries") { Text(history.totalCount.formatted()) }
                LabeledContent("File size") { Text(history.fileSize.formatted(.byteCount(style: .file))) }
                Button("Clear history…", role: .destructive) { isConfirmingClear = true }
                    .disabled(history.totalCount == 0)
                    .clickable()
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await history.clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every entry from the history file. Your packages are not changed.")
        }
    }
}
