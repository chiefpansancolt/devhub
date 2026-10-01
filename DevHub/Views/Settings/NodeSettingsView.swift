import DevHubCore
import SwiftUI

struct NodeSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let found = Toolchain.detect(settings: settings.values, applyingExclusions: false).node

        Form {
            Section("Location") {
                PathRow(
                    title: "Version manager folder",
                    chosenPath: $settings.values.nodeFolder,
                    detectedText: detectedText(found),
                    check: check(found),
                    kind: .folder
                )
            }

            if !found.isEmpty {
                Section("Node versions to check") {
                    ForEach(found) { installation in
                        Toggle(isOn: isIncluded(installation.version)) {
                            HStack {
                                Text("v\(installation.version)")
                                Spacer()
                                Text("^[\(state.packages(in: PackageScope(bucket: .node, group: installation.version)).count) global package](inflect: true)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clickable()
                    }
                }
            }

            Section("Updating") {
                Toggle("Include npm itself", isOn: $settings.values.nodeIncludeNpm)
                .clickable()
            }
        }
        .formStyle(.grouped)
    }

    private func isIncluded(_ version: String) -> Binding<Bool> {
        Binding(
            get: { !settings.values.excludedNodeVersions.contains(version) },
            set: { isOn in
                if isOn { settings.values.excludedNodeVersions.remove(version) } else { settings.values.excludedNodeVersions.insert(version) }
            }
        )
    }

    private func detectedText(_ found: [NodeInstallation]) -> String {
        let managers = Set(found.map(\.manager)).filter { $0 != .custom }.map(\.rawValue).sorted()
        return managers.isEmpty
            ? String(localized: "Nothing found in the usual places")
            : String(localized: "Found automatically: \(managers.formatted(.list(type: .and, width: .narrow)))")
    }

    private func check(_ found: [NodeInstallation]) -> PathCheck {
        if let path = settings.values.nodeFolder { return PathValidation.nodeFolder(path: path) }
        if found.isEmpty { return .problem(String(localized: "No Node version manager found. Choose the folder that holds your Node versions.")) }
        return .found(found.count == 1 ? String(localized: "1 version found") : String(localized: "\(found.count) versions found"))
    }
}
