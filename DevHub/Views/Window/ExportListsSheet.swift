import DevHubCore
import SwiftUI

struct ExportListsSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var unchecked: Set<Bucket> = []

    private var lists: StandardPackageLists { settings.values.standardPackages }
    private var chosen: Set<Bucket> { Set(StandardListsFile.tools(in: lists)).subtracting(unchecked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Export standard packages").font(.system(size: 17, weight: .semibold))
                Text("Writes your standard packages lists to one file. Installed packages are not included.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            Text("Include").textCase(.uppercase).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
            ForEach(Bucket.allCases, id: \.self) { bucket in
                Divider()
                toolRow(bucket)
            }
            Divider()
            Text("File: \(StandardListsFileActions.fileName)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .clickable()
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .clickable()
                    .disabled(chosen.isEmpty)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 500)
    }

    private func toolRow(_ bucket: Bucket) -> some View {
        let count = lists.entries(for: bucket).count
        return Toggle(isOn: Binding(
            get: { count > 0 && !unchecked.contains(bucket) },
            set: { isOn in if isOn { unchecked.remove(bucket) } else { unchecked.insert(bucket) } }
        )) {
            HStack {
                Text(verbatim: bucket.displayName).fontWeight(.semibold)
                Spacer()
                if count > 0 {
                    Text("Packages: \(count)").foregroundStyle(.secondary)
                } else {
                    Text("Empty list").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .clickable()
        .disabled(count == 0)
        .padding(.vertical, 9)
    }

    private func export() {
        let file = StandardListsFile.make(from: lists, tools: chosen, now: Date())
        if StandardListsFileActions.export(file) { dismiss() }
    }
}
