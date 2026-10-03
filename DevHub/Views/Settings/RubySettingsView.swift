import DevHubCore
import SwiftUI

struct RubySettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let found = Toolchain.detect(settings: settings.values, applyingExclusions: false).ruby

        Form {
            Section {
                PathRow(
                    title: "Version manager folder",
                    chosenPath: $settings.values.rubyFolder,
                    detectedText: detectedText(found),
                    check: check(found),
                    kind: .folder
                )
            } header: {
                Label {
                    Text("Location")
                } icon: {
                    BucketBadge(bucket: .ruby, size: 14)
                }
            }

            if !found.isEmpty {
                Section("Ruby versions to check") {
                    ForEach(found) { installation in
                        Toggle(isOn: isIncluded(installation.version)) {
                            HStack {
                                Text(installation.version)
                                Spacer()
                                Text("\(state.packages(in: PackageScope(bucket: .ruby, group: installation.version)).count) gems")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clickable()
                    }
                }
            }

            Section("New versions") {
                Toggle("Check for new Ruby versions", isOn: checksForNewVersions)
                    .clickable()
                Text("Looks up the newest release on ruby-lang.org once a day. When a version is missing, a banner offers to install it with your version manager.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Standard gems") {
                LabeledContent("Standard gems") {
                    ManageStandardPackagesButton(bucket: .ruby)
                }
                Text("Managed in their own window, where you can check the list and install it into a Ruby version.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Toggle("Offer the standard gems in new versions", isOn: offersStandardPackages)
                    .clickable()
                Text("Shows a banner in the window when a Ruby version is missing some of them. Nothing installs until you choose Install.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Update options") {
                Toggle("Install gem documentation", isOn: $settings.values.gemInstallDocumentation)
                .clickable()
                Text("Slower, and uses more disk space.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var checksForNewVersions: Binding<Bool> {
        Binding(
            get: { !settings.values.disabledRuntimeChecks.contains("ruby") },
            set: { isOn in
                if isOn { settings.values.disabledRuntimeChecks.remove("ruby") } else { settings.values.disabledRuntimeChecks.insert("ruby") }
            }
        )
    }

    private var offersStandardPackages: Binding<Bool> {
        Binding(
            get: { !settings.values.disabledStandardBanners.contains("ruby") },
            set: { isOn in
                if isOn { settings.values.disabledStandardBanners.remove("ruby") } else { settings.values.disabledStandardBanners.insert("ruby") }
            }
        )
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
        return .found(String(localized: "\(found.count) versions found"))
    }
}
