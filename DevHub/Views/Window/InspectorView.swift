import DevHubCore
import SwiftUI

struct InspectorView: View {
    @Environment(AppState.self) private var state
    let ui: WindowUIState

    var body: some View {
        if let package = ui.inspectedID.flatMap({ state.package(withID: $0) }) {
            InspectorContent(package: package, ui: ui)
        }
    }
}

private struct InspectorContent: View {
    @Environment(AppState.self) private var state
    let package: InstalledPackage
    let ui: WindowUIState
    @State private var diskSize: DiskSizeState = .unknown

    private enum DiskSizeState {
        case unknown
        case measuring
        case measured(Int64)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let summary = package.summary {
                Text(summary)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                        FieldRow(label: field.label, value: field.value, isMonospaced: field.isMonospaced)
                    }
                }
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .task(id: package.id) { await measureDiskSize() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(package.name)
                    .font(.system(size: 16, weight: .semibold))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Chip(text: Text(kindLabel), style: .plain)
                    if package.isOutdated {
                        Chip(text: Text("Update available"), style: .accent)
                    } else {
                        Chip(text: Text("Up to date"), style: .success)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                ui.closeInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .clickable()
            .accessibilityLabel("Close details")
        }
        .padding(16)
    }

    private var kindLabel: String {
        switch package.kind {
        case .formula: "Formula"
        case .cask: "Cask"
        case .npmGlobal: "npm global · Node \(package.group ?? "")"
        case .gem: "Gem · Ruby \(package.group ?? "")"
        }
    }

    // MARK: Fields

    private struct Field {
        let label: LocalizedStringKey
        let value: String
        var isMonospaced = false
    }

    private var fields: [Field] {
        var fields = [Field(label: "Installed version", value: package.installedVersion)]
        if let latest = package.availableUpdate {
            fields.append(Field(label: "Latest version", value: latest))
        }
        switch diskSize {
        case .unknown: break
        case .measuring: fields.append(Field(label: "Disk size", value: String(localized: "Calculating…")))
        case let .measured(bytes): fields.append(Field(label: "Disk size", value: bytes.formatted(.byteCount(style: .file))))
        }
        if let path = package.installPath {
            fields.append(Field(label: "Location", value: path, isMonospaced: true))
        }
        if let homepage = package.homepage {
            fields.append(Field(label: "Source", value: homepage, isMonospaced: true))
        }
        if !package.requiredBy.isEmpty {
            fields.append(Field(label: "Required by", value: package.requiredBy.formatted(.list(type: .and, width: .narrow))))
        }
        if package.bucket == .homebrew, !package.installedOnRequest {
            fields.append(Field(label: "Installed as", value: String(localized: "A dependency of another package")))
        }
        return fields
    }

    private func measureDiskSize() async {
        guard let path = package.installPath else {
            diskSize = .unknown
            return
        }
        diskSize = .measuring
        if let bytes = await DiskSize.measure(path: path) {
            diskSize = .measured(bytes)
        } else {
            diskSize = .unknown
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if let progress = state.uninstallProgress, progress.packageID == package.id {
            uninstallProgress(progress)
        } else if ui.isConfirmingUninstall {
            uninstallConfirmation
        } else {
            VStack(spacing: 10) {
                if let latest = package.availableUpdate {
                    Button {
                        state.startUpdate([package])
                    } label: {
                        Text("Update to \(latest)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isBusy)
                    .clickable()
                }
                Button {
                    ui.isConfirmingUninstall = true
                } label: {
                    Text("Uninstall…").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .foregroundStyle(.red)
                .disabled(state.isBusy)
                .clickable()
            }
        }
    }

    private var uninstallConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uninstall \(package.name)?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
            Text(consequence).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            if let command = state.uninstallCommandText(for: package) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button { ui.isConfirmingUninstall = false } label: { Text("Cancel").frame(maxWidth: .infinity) }
                    .clickable()
                Button {
                    ui.isConfirmingUninstall = false
                    state.startUninstall(package)
                } label: {
                    Text("Uninstall").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .clickable()
            }
            .controlSize(.large)
        }
        .padding(12)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func uninstallProgress(_ progress: UninstallProgress) -> some View {
        switch progress.status {
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Uninstall failed", systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text(message).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
                Button { state.dismissUninstallFailure() } label: { Text("Dismiss").frame(maxWidth: .infinity) }
                    .controlSize(.large)
                    .clickable()
            }
            .padding(12)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Removing \(package.name)").font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var consequence: String {
        switch package.bucket {
        case .homebrew:
            if package.requiredBy.isEmpty {
                return String(localized: "Nothing else installed depends on it. Its files are removed from disk.")
            }
            let names = package.requiredBy.formatted(.list(type: .and, width: .narrow))
            return String(localized: "Other installed packages need this: \(names). They may stop working.")
        case .node:
            return String(localized: "It is removed from the global packages of Node \(package.group ?? "").")
        case .ruby:
            return String(localized: "Every installed version of this gem is removed from Ruby \(package.group ?? "").")
        }
    }
}

private struct FieldRow: View {
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

private struct Chip: View {
    enum Style { case plain, accent, success }

    let text: Text
    let style: Style

    var body: some View {
        text
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(style == .plain ? Color.secondary.opacity(0.35) : .clear))
    }

    private var foreground: Color {
        switch style {
        case .plain: .secondary
        case .accent: .accentColor
        case .success: .green
        }
    }

    private var background: Color {
        switch style {
        case .plain: .clear
        case .accent: Color.accentColor.opacity(0.14)
        case .success: .clear
        }
    }
}
