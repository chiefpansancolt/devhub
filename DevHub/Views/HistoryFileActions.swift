import AppKit
import DevHubCore

/// The file actions that the History page and the History settings share.
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
        Task { try? await history.export(to: destination) }
    }
}
