import AppKit
import DevHubCore
import UniformTypeIdentifiers

@MainActor
enum StandardListsFileActions {
    static let fileName = "devhub-standard-packages.json"

    /// Asks where to save the file and writes it. Returns false when the person cancels or the file cannot be written.
    @discardableResult
    static func export(_ file: StandardListsFile) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            try file.encoded().write(to: destination, options: .atomic)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Asks for a file and reads it. A file that cannot be read shows an alert.
    static func chooseImport() -> PendingImport? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let decoded = try StandardListsFile.decode(Data(contentsOf: url))
            return PendingImport(fileName: url.lastPathComponent, decoded: decoded)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}
