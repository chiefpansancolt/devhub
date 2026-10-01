import DevHubCore
import SwiftUI

struct RubySettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let found = Toolchain.detect(settings: settings.values, applyingExclusions: false).ruby

        Form {
            Section("Location") {
                PathRow(
                    title: "Version manager folder",
                    chosenPath: $settings.values.rubyFolder,
                    detectedText: detectedText(found),
                    check: check(found),
                    kind: .folder
                )
            }

            if !found.isEmpty {
                Section("Ruby versions to check") {
                    ForEach(found) { installation in
                        Toggle(isOn: isIncluded(installation.version)) {
                            HStack {
                                Text(installation.version)
                                Spacer()
                                Text("^[\(state.packages(in: PackageScope(bucket: .ruby, group: installation.version)).count) gem](inflect: true)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Updating") {
                Toggle("Install gem documentation", isOn: $settings.values.gemInstallDocumentation)
                Text("Slower, and uses more disk space.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func isIncluded(_ version: String) -> Binding<Bool> {
        Binding(
            get: { !settings.values.excludedRubyVersions.contains(version) },
            set: { isOn in
                if isOn { settings.values.excludedRubyVersions.remove(version) } else { settings.values.excludedRubyVersions.insert(version) }
            }
        )
    }

    private func detectedText(_ found: [RubyInstallation]) -> String {
        let managers = Set(found.map(\.manager)).filter { $0 != .custom }.map(\.rawValue).sorted()
        return managers.isEmpty
            ? String(localized: "Nothing found in the usual places")
            : String(localized: "Found automatically: \(managers.formatted(.list(type: .and, width: .narrow)))")
    }

    private func check(_ found: [RubyInstallation]) -> PathCheck {
        if let path = settings.values.rubyFolder { return PathValidation.rubyFolder(path: path) }
        if found.isEmpty { return .problem(String(localized: "No Ruby version manager found. Choose the folder that holds your Ruby versions.")) }
        return .found(found.count == 1 ? String(localized: "1 version found") : String(localized: "\(found.count) versions found"))
    }
}
