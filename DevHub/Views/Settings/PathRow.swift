import AppKit
import DevHubCore
import SwiftUI

enum PathKind {
    case file
    case folder
}

/// A path the person can choose, with a status line that says whether it works.
struct PathRow: View {
    let title: LocalizedStringKey
    @Binding var chosenPath: String?
    /// What to show while the person has chosen nothing.
    let detectedText: String
    /// `nil` while the check is running.
    let check: PathCheck?
    let kind: PathKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fontWeight(.semibold)
            HStack(spacing: 8) {
                Text(chosenPath ?? detectedText)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button("Choose…") { choose() }
                    .clickable()
                if chosenPath != nil {
                    Button("Reset to detected") { chosenPath = nil }
                        .buttonStyle(.borderless)
                        .clickable()
                }
            }
            status
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var status: some View {
        switch check {
        case nil:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        case let .found(text)?:
            Label(text, systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case let .problem(text)?:
            Label(text, systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind == .file
        panel.canChooseDirectories = kind == .folder
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let chosenPath {
            panel.directoryURL = URL(filePath: chosenPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chosenPath = url.path
    }
}
