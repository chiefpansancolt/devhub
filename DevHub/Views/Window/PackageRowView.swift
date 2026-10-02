import DevHubCore
import SwiftUI

struct PackageRowView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    let package: InstalledPackage
    let ui: WindowUIState

    var body: some View {
        let isInspected = ui.inspectedID == package.id
        HStack(spacing: 12) {
            Toggle("Select \(package.name)", isOn: Binding(
                get: { ui.checkedIDs.contains(package.id) },
                set: { isOn in
                    if isOn { ui.checkedIDs.insert(package.id) } else { ui.checkedIDs.remove(package.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .clickable()
            .disabled(!package.isOutdated)
            .frame(width: Columns.checkbox)

            Button {
                ui.toggleInspector(for: package)
            } label: {
                HStack(spacing: 12) {
                    Text(package.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    kind.foregroundStyle(.secondary).frame(width: Columns.kind, alignment: .leading)
                    Text(package.installedVersion).foregroundStyle(.secondary).lineLimit(1).frame(width: Columns.version, alignment: .leading)
                    Text(package.availableUpdate ?? package.installedVersion)
                        .foregroundStyle(package.isOutdated ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(width: Columns.version, alignment: .leading)
                }
                .font(.system(size: 13))
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickable()
            .accessibilityLabel("Show details for \(package.name)")
            .accessibilityValue(package.availableUpdate.map { "Installed \(package.installedVersion), update to \($0)" } ?? "Installed \(package.installedVersion), up to date")
            .accessibilityAddTraits(isInspected ? .isSelected : [])

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                statusOrAction
                Button {
                    if settings.values.confirmUninstall {
                        ui.askToUninstall(package)
                    } else {
                        state.startUninstall(package)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .clickable()
                .disabled(state.isBusy)
                .accessibilityLabel("Uninstall \(package.name)")
            }
            .frame(width: Columns.actions)
        }
        .padding(.horizontal, 20)
        .background(isInspected ? Color.accentColor.opacity(0.14) : .clear)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var kind: Text {
        switch package.bucket {
        case .homebrew: package.kind == .cask ? Text("Cask") : Text("Formula")
        case .node, .ruby: Text(verbatim: package.group ?? "")
        }
    }

    @ViewBuilder
    private var statusOrAction: some View {
        if let progress = state.uninstallProgress, progress.packageID == package.id, progress.status == .updating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Removing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } else if state.session?.isRunning == true, let status = state.status(of: package) {
            UpdateStatusLabel(status: status)
        } else if package.isOutdated {
            Button("Update") { state.startUpdate([package]) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clickable()
                .disabled(state.isBusy)
                .accessibilityLabel("Update \(package.name)")
        } else {
            Label("Current", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        }
    }
}

struct UpdateStatusLabel: View {
    let status: UpdateStatus

    var body: some View {
        switch status {
        case .waiting:
            Text("Waiting").font(.system(size: 12)).foregroundStyle(.secondary)
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .done:
            Label("Done", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(.green)
        case let .failed(message):
            Label("Failed", systemImage: "xmark").font(.system(size: 12)).foregroundStyle(.red).help(message)
        case .skipped:
            Text("Skipped").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
