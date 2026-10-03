import DevHubCore
import SwiftUI

struct PythonSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var pipxCheck: PathCheck?
    @State private var uvCheck: PathCheck?

    var body: some View {
        @Bindable var settings = settings
        let found = Toolchain.detect(settings: settings.values, applyingExclusions: false).python
        let pipxPath = settings.values.pipxPath ?? found.first { $0.manager == .pipx }?.executable.path
        let uvPath = settings.values.uvPath ?? found.first { $0.manager == .uv }?.executable.path

        Form {
            Section {
                PathRow(
                    title: "pipx program",
                    chosenPath: $settings.values.pipxPath,
                    detectedText: detectedPath(of: .pipx, in: found),
                    check: pipxCheck,
                    kind: .file,
                    showsStatus: pipxPath != nil
                )
                PathRow(
                    title: "uv program",
                    chosenPath: $settings.values.uvPath,
                    detectedText: detectedPath(of: .uv, in: found),
                    check: uvCheck,
                    kind: .file,
                    showsStatus: uvPath != nil
                )
            } header: {
                Label {
                    Text("Location")
                } icon: {
                    BucketBadge(bucket: .python, size: 14)
                }
            }

            if !found.isEmpty {
                Section("Tool managers to check") {
                    ForEach(found) { installation in
                        Toggle(isOn: isIncluded(installation.manager)) {
                            HStack {
                                Text(verbatim: installation.manager.rawValue)
                                Spacer()
                                Text("\(state.packages(in: PackageScope(bucket: .python, group: installation.manager.rawValue)).count) tools")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clickable()
                    }
                }
            }

            Section("Standard packages") {
                LabeledContent("Standard packages") {
                    ManageStandardPackagesButton(bucket: .python)
                }
                Text("Managed in their own window, where you can check the list and install it with pipx or uv.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: pipxPath) { pipxCheck = await validate(.pipx, path: pipxPath) }
        .task(id: uvPath) { uvCheck = await validate(.uv, path: uvPath) }
    }

    private func validate(_ manager: PythonManager, path: String?) async -> PathCheck? {
        guard let path else { return nil }
        return await PathValidation.pythonManager(manager, path: path, runner: CommandRunner())
    }

    private func detectedPath(of manager: PythonManager, in found: [PythonInstallation]) -> String {
        found.first { $0.manager == manager }?.executable.path ?? String(localized: "Not found in the usual places")
    }

    private func isIncluded(_ manager: PythonManager) -> Binding<Bool> {
        Binding(
            get: { !settings.values.excludedPythonManagers.contains(manager.rawValue) },
            set: { isOn in
                if isOn { settings.values.excludedPythonManagers.remove(manager.rawValue) } else { settings.values.excludedPythonManagers.insert(manager.rawValue) }
            }
        )
    }
}
