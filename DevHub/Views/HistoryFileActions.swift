import AppKit
import DevHubCore

@MainActor
enum HistoryFileActions {
    static func showInFinder(_ history: HistoryStore) {
        guard let url = history.fileURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    static func export(_ history: HistoryStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "devhub-history.jsonl"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await history.export(to: destination)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
