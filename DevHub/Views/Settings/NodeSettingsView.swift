import DevHubCore
import SwiftUI

struct NodeSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @Environment(WindowUIState.self) private var windowUI
    @Environment(\.openWindow) private var openWindow
    @State private var managerChecks: [NodePackageManager: PathCheck] = [:]

    var body: some View {
        @Bindable var settings = settings
        let toolchain = Toolchain.detect(settings: settings.values, applyingExclusions: false)
        let found = toolchain.node
        let managers = toolchain.nodeManagers

        Form {
            Section {
                PathRow(
                    title: "Version manager folder",
                    chosenPath: $settings.values.nodeFolder,
                    detectedText: detectedText(found),
                    check: check(found),
                    kind: .folder
                )
            } header: {
                Label {
                    Text("Location")
                } icon: {
                    BucketBadge(bucket: .node, size: 14)
                }
            }

            if !found.isEmpty {
                Section("Node versions to check") {
                    ForEach(found) { installation in
                        Toggle(isOn: isIncluded(installation.version)) {
                            HStack {
                                Text("v\(installation.version)")
                                Spacer()
                                Text("\(state.packages(in: PackageScope(bucket: .node, group: installation.version)).count) global packages")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clickable()
                    }
                }
            }

            Section("Other package managers") {
                managerRow(.pnpm, title: "pnpm program", chosenPath: $settings.values.pnpmPath, managers)
                managerRow(.bun, title: "Bun program", chosenPath: $settings.values.bunPath, managers)
                managerRow(.yarn, title: "Yarn program", chosenPath: $settings.values.yarnPath, managers)
            }

            if !managers.isEmpty {
                Section("Package managers to check") {
                    ForEach(managers) { installation in
                        Toggle(isOn: isIncluded(installation.manager)) {
                            HStack {
                                Text(verbatim: installation.manager.displayName)
                                Spacer()
                                Text("\(state.packages(in: PackageScope(bucket: .node, group: installation.manager.displayName)).count) global packages")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clickable()
                    }
                }
            }

            Section("Standard packages") {
                LabeledContent("Standard packages") {
                    Button("Manage…") { manageStandardPackages() }
                        .clickable()
                }
                Text("Managed in their own window, where you can check the list and install it into a Node version.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Toggle("Offer the standard packages in new versions", isOn: offersStandardPackages)
                    .clickable()
                Text("Shows a banner in the window when a Node version is missing some of them. Nothing installs until you choose Install.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Update options") {
                Toggle("Include npm itself", isOn: $settings.values.nodeIncludeNpm)
                .clickable()
            }
        }
        .formStyle(.grouped)
        .task(id: effectivePath(of: .pnpm, in: managers)) { await validate(.pnpm, in: managers) }
        .task(id: effectivePath(of: .bun, in: managers)) { await validate(.bun, in: managers) }
        .task(id: effectivePath(of: .yarn, in: managers)) { await validate(.yarn, in: managers) }
    }

    private func managerRow(
        _ manager: NodePackageManager,
        title: LocalizedStringKey,
        chosenPath: Binding<String?>,
        _ managers: [NodePackageManagerInstallation]
    ) -> some View {
        PathRow(
            title: title,
            chosenPath: chosenPath,
            detectedText: detectedPath(of: manager, in: managers) ?? String(localized: "Not found in the usual places"),
            check: managerChecks[manager],
            kind: .file,
            showsStatus: effectivePath(of: manager, in: managers) != nil
        )
    }

    private func detectedPath(of manager: NodePackageManager, in managers: [NodePackageManagerInstallation]) -> String? {
        managers.first { $0.manager == manager }?.executable.path
    }

    private func chosenPath(of manager: NodePackageManager) -> String? {
        switch manager {
        case .pnpm: settings.values.pnpmPath
        case .bun: settings.values.bunPath
        case .yarn: settings.values.yarnPath
        }
    }

    private func effectivePath(of manager: NodePackageManager, in managers: [NodePackageManagerInstallation]) -> String? {
        chosenPath(of: manager) ?? detectedPath(of: manager, in: managers)
    }

    private func validate(_ manager: NodePackageManager, in managers: [NodePackageManagerInstallation]) async {
        managerChecks[manager] = nil
        guard let path = effectivePath(of: manager, in: managers) else { return }
        managerChecks[manager] = await PathValidation.nodeManager(manager, path: path, runner: CommandRunner())
    }

    private var offersStandardPackages: Binding<Bool> {
        Binding(
            get: { !settings.values.disabledStandardBanners.contains("node") },
            set: { isOn in
                if isOn { settings.values.disabledStandardBanners.remove("node") } else { settings.values.disabledStandardBanners.insert("node") }
            }
        )
    }

    private func manageStandardPackages() {
        windowUI.sheet = .standardPackages(.node)
        openWindow(id: MainWindow.id)
        AppActivation.bringToFront()
    }

    private func isIncluded(_ manager: NodePackageManager) -> Binding<Bool> {
        Binding(
            get: { !settings.values.excludedNodeManagers.contains(manager.rawValue) },
            set: { isOn in
                if isOn { settings.values.excludedNodeManagers.remove(manager.rawValue) } else { settings.values.excludedNodeManagers.insert(manager.rawValue) }
            }
        )
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
        return .found(String(localized: "\(found.count) versions found"))
    }
}
