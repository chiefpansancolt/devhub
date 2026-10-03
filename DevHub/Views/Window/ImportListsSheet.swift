import DevHubCore
import SwiftUI

struct ImportListsSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let ui: WindowUIState
    @State private var mode = ImportMode.merge
    @State private var unchecked: Set<Bucket> = []

    private static let shownNames = 8

    private var pending: PendingImport? { ui.pendingImport }

    private var plan: ImportPlan? {
        pending.map { StandardListsImporter.plan(for: $0.decoded, into: settings.values.standardPackages, mode: mode) }
    }

    private var chosen: Set<Bucket> { Set(plan?.changedTools ?? []).subtracting(unchecked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pending, let plan {
                header(pending)
                modeBar
                if plan.skippedEntries > 0 {
                    Text("Entries DevHub cannot use were ignored: \(plan.skippedEntries)")
                        .font(.system(size: 12))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                        .padding(.bottom, 8)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(plan.tools) { tool in
                            Divider()
                            toolRow(tool)
                        }
                        if plan.tools.isEmpty {
                            Divider()
                            Text("The file has no lists.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 14)
                        }
                    }
                }
                Divider()
                footer(plan)
            }
        }
        .padding(24)
        .frame(width: 600, height: 520)
    }

    private func header(_ pending: PendingImport) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Import standard packages").font(.system(size: 17, weight: .semibold))
            Text(verbatim: sourceLine(pending)).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    private func sourceLine(_ pending: PendingImport) -> String {
        guard let date = pending.decoded.file.exportedAt else { return pending.fileName }
        return String(localized: "\(pending.fileName) · exported \(date.formatted(date: .abbreviated, time: .omitted))")
    }

    private var modeBar: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("Merge adds the names that are not in your lists yet. Replace swaps each list for the one in the file. Nothing is installed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Mode", selection: $mode) {
                Text("Merge").tag(ImportMode.merge)
                Text("Replace").tag(ImportMode.replace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .clickable()
        }
        .padding(.bottom, 10)
    }

    private func toolRow(_ tool: ImportToolPlan) -> some View {
        Toggle(isOn: Binding(
            get: { tool.changesTheList && !unchecked.contains(tool.bucket) },
            set: { isOn in if isOn { unchecked.remove(tool.bucket) } else { unchecked.insert(tool.bucket) } }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(verbatim: tool.bucket.displayName).fontWeight(.semibold)
                    summary(tool).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(verbatim: names(of: tool))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .toggleStyle(.checkbox)
        .clickable()
        .disabled(!tool.changesTheList)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func summary(_ tool: ImportToolPlan) -> Text {
        guard tool.changesTheList else { return Text("Nothing to change") }
        switch mode {
        case .merge: return Text("Adds \(tool.toAdd.count) · \(tool.alreadyThere.count) already in your list")
        case .replace: return Text("Adds \(tool.toAdd.count) · Removes \(tool.toRemove.count)")
        }
    }

    private func names(of tool: ImportToolPlan) -> String {
        let shown = tool.changesTheList ? tool.toAdd + tool.toRemove : tool.alreadyThere
        let names = shown.map(\.name)
        let more = names.count - Self.shownNames
        return names.prefix(Self.shownNames).joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    private func footer(_ plan: ImportPlan) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .clickable()
            Button("Import") { apply(plan) }
                .keyboardShortcut(.defaultAction)
                .clickable()
                .disabled(chosen.isEmpty)
        }
        .padding(.top, 14)
    }

    private func apply(_ plan: ImportPlan) {
        guard let pending else { return }
        var lists = settings.values.standardPackages
        StandardListsImporter.apply(plan, tools: chosen, to: &lists)
        settings.values.standardPackages = lists

        let applied = plan.tools.filter { chosen.contains($0.bucket) }
        let summary = mode == .merge
            ? String(localized: "Added: \(applied.reduce(0) { $0 + $1.toAdd.count }) · Already there: \(applied.reduce(0) { $0 + $1.alreadyThere.count })")
            : String(localized: "Lists replaced: \(applied.count)")
        ui.standardPackagesNotice = String(localized: "Imported from \(pending.fileName). \(summary). Validate to check them.")
        ui.pendingImport = nil
        let tool = applied.first?.bucket ?? .node
        ui.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            ui.sheet = .standardPackages(tool)
        }
    }
}
