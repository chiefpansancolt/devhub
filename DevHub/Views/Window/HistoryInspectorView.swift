import AppKit
import DevHubCore
import SwiftUI

struct HistoryInspectorView: View {
    @Environment(AppState.self) private var state
    let ui: WindowUIState

    var body: some View {
        if let entry = ui.inspectedHistoryID.flatMap({ id in state.history.entries.first { $0.id == id } }) {
            HistoryInspectorContent(entry: entry, ui: ui)
        }
    }
}

private struct HistoryInspectorContent: View {
    @Environment(AppState.self) private var state
    let entry: HistoryEntry
    let ui: WindowUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                        HistoryFieldRow(label: field.label, value: field.value, isMonospaced: field.isMonospaced)
                    }
                    if let output = entry.output, !output.isEmpty {
                        outputBlock(output)
                    }
                }
            }
            if showsFooter {
                Divider()
                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.package ?? String(localized: "Check for updates"))
                    .font(.system(size: 16, weight: .semibold))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(entry.action.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
                    ResultChip(ok: entry.ok)
                }
            }
            Spacer(minLength: 0)
            Button {
                ui.inspectedHistoryID = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .clickable()
            .accessibilityLabel("Close details")
        }
        .padding(16)
    }

    // MARK: Fields

    private struct Field {
        let label: LocalizedStringKey
        let value: String
        var isMonospaced = false
    }

    private var fields: [Field] {
        var fields = [Field(label: "Time", value: entry.timestamp.formatted(date: .complete, time: .standard))]
        if !entry.ok, let message = entry.message {
            fields.append(Field(label: "Reason", value: message))
        }
        if let bucket = entry.bucket {
            fields.append(Field(label: "Bucket", value: [bucket.displayName, entry.group].compactMap { $0 }.joined(separator: " ")))
        }
        if entry.action != .check {
            fields.append(Field(label: "Change", value: entry.changeText))
        } else if entry.ok, let message = entry.message {
            fields.append(Field(label: "Result", value: message))
        }
        fields.append(Field(label: "Started by", value: startedBy))
        fields.append(Field(label: "Duration", value: entry.durationMs.formatted(.number) + " ms"))
        fields.append(Field(label: "Exit code", value: String(entry.exitCode), isMonospaced: true))
        fields.append(Field(label: "Command", value: entry.command, isMonospaced: true))
        return fields
    }

    private var startedBy: String {
        switch entry.trigger {
        case .manual: String(localized: "Manual")
        case .updateAll: String(localized: "Update all")
        case .automatic: String(localized: "Automatic check")
        }
    }

    private func outputBlock(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(entry.ok ? Color(red: 0.85, green: 0.85, blue: 0.86) : Color(red: 1.0, green: 0.54, blue: 0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding(10)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Footer

    private var showsFooter: Bool {
        canRetry || !(entry.output ?? []).isEmpty
    }

    /// A failed update can run again while the package still has an update. A failed check can always run again.
    private var retryablePackage: InstalledPackage? {
        guard entry.action == .update, !entry.ok, let name = entry.package, let bucket = entry.bucket else { return nil }
        return state.packages(in: PackageScope(bucket: bucket)).first {
            $0.name == name && $0.group == entry.group && $0.isOutdated
        }
    }

    private var canRetry: Bool {
        !entry.ok && (entry.action == .check || retryablePackage != nil)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if canRetry {
                Button {
                    if let package = retryablePackage {
                        state.startUpdate([package])
                    } else {
                        state.startRefresh()
                    }
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .clickable()
                .disabled(state.isBusy)
            }
            if let output = entry.output, !output.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output.joined(separator: "\n"), forType: .string)
                } label: {
                    Text("Copy output").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .clickable()
            }
        }
    }
}

private struct HistoryFieldRow: View {
    let label: LocalizedStringKey
    let value: String
    let isMonospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider() }
    }
}
