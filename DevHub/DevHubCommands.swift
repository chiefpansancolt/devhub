import AppKit
import DevHubCore
import SwiftUI

struct DevHubCommands: Commands {
    let state: AppState
    let settings: SettingsStore
    let ui: WindowUIState
    @Environment(\.openWindow) private var openWindow

    private static let issuesURL = URL(string: "https://github.com/chiefpansancolt/devhub/issues/new")!

    // MARK: What the menus act on

    private var selectedPackage: InstalledPackage? {
        ui.page == .packages ? ui.inspectedID.flatMap { state.package(withID: $0) } : nil
    }

    private var outdatedInScope: [InstalledPackage] { state.outdated(in: ui.scope) }

    private var checkedPackages: [InstalledPackage] { outdatedInScope.filter { ui.checkedIDs.contains($0.id) } }

    var body: some Commands {
        appCommands
        fileCommands
        editCommands
        viewCommands
        packageCommands
        helpCommands
    }

    // MARK: App

    private var appCommands: some Commands {
        Group {
            CommandGroup(replacing: .appInfo) {
                Button("About DevHub") { AboutPanel.show() }
            }
            CommandGroup(after: .appSettings) {
                Button("Standard Packages…") { showStandardPackages() }
                    .disabled(state.enabledBuckets.isEmpty)
            }
        }
    }

    private func showStandardPackages() {
        show(.standardPackages(.node))
    }

    private func show(_ sheet: WindowSheet) {
        ui.sheet = sheet
        openWindow(id: MainWindow.id)
        AppActivation.bringToFront()
    }

    private func importStandardPackages() {
        guard let pending = StandardListsFileActions.chooseImport() else { return }
        ui.pendingImport = pending
        show(.importLists)
    }

    // MARK: File

    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Refresh All") { state.startRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isChecking || state.isBusy)
            Divider()
            Button("Update All") { updateAll() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(outdatedInScope.isEmpty || state.isBusy)
            Button("Update Selected") { state.startUpdate(checkedPackages) }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(checkedPackages.isEmpty || state.isBusy)
            Divider()
            Button("Export Standard Packages…") { show(.exportLists) }
                .disabled(settings.values.standardPackages.isEmpty)
            Button("Import Standard Packages…") { importStandardPackages() }
        }
    }

    // The Mac shows the confirmation on the packages page, so the command goes there first.
    private func updateAll() {
        ui.select(ui.scope)
        if settings.values.confirmUpdateAll {
            ui.isConfirmingUpdateAll = true
        } else {
            state.startUpdate(outdatedInScope)
        }
    }

    // MARK: Edit

    private var editCommands: some Commands {
        Group {
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Package Name") { copy(selectedPackage?.name) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(selectedPackage == nil)
                Button("Select All Updates") { ui.checkedIDs.formUnion(outdatedInScope.map(\.id)) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .disabled(ui.page != .packages || outdatedInScope.isEmpty)
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { ui.requestSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    // MARK: View

    private var viewCommands: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(state.enabledBuckets, id: \.self) { bucket in
                Toggle(bucket.displayName, isOn: Binding(
                    get: { ui.page == .packages && ui.scope.bucket == bucket },
                    set: { _ in ui.select(PackageScope(bucket: bucket)) }
                ))
                .keyboardShortcut(KeyEquivalent(bucket.shortcutKey), modifiers: .command)
            }
            Divider()
            Toggle("Show Updates", isOn: Binding(
                get: { ui.page == .packages && ui.mode == .updates },
                set: { _ in showList(.updates) }
            ))
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(state.enabledBuckets.isEmpty)
            Toggle("Show All Installed", isOn: Binding(
                get: { ui.page == .packages && ui.mode == .allInstalled },
                set: { _ in showList(.allInstalled) }
            ))
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(state.enabledBuckets.isEmpty)
            Toggle("Show History", isOn: Binding(get: { ui.page == .history }, set: { _ in ui.showHistory() }))
                .keyboardShortcut("6", modifiers: .command)
            Divider()
            Button(ui.hasOpenDetails ? "Hide Details Pane" : "Show Details Pane") {
                if ui.hasOpenDetails { ui.hideDetails() } else { ui.showDetails() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!ui.hasOpenDetails && !ui.canShowDetails)
            Button(settings.values.showOutputLog ? "Hide Output Log" : "Show Output Log") {
                settings.values.showOutputLog.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }
    }

    private func showList(_ mode: PackageListMode) {
        ui.mode = mode
        ui.select(ui.scope)
    }

    // MARK: Package

    private var packageCommands: some Commands {
        CommandMenu("Package") {
            Button("Update") { if let package = selectedPackage { state.startUpdate([package]) } }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(selectedPackage?.isOutdated != true || state.isBusy)
            Button("Uninstall…") { if let package = selectedPackage { uninstall(package) } }
                .keyboardShortcut(.delete, modifiers: [.command, .control])
                .disabled(selectedPackage == nil || state.isBusy)
            Divider()
            Button("Open Source Page") {
                if let text = selectedPackage?.homepage, let url = URL(string: text) { NSWorkspace.shared.open(url) }
            }
            .disabled(selectedPackage?.homepage == nil)
            Button("Copy Install Path") { copy(selectedPackage?.installPath) }
                .disabled(selectedPackage?.installPath == nil)
            Button("Show in Finder") {
                if let path = selectedPackage?.installPath {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                }
            }
            .disabled(selectedPackage?.installPath == nil)
        }
    }

    private func uninstall(_ package: InstalledPackage) {
        if settings.values.confirmUninstall {
            ui.askToUninstall(package)
        } else {
            state.startUninstall(package)
        }
    }

    // MARK: Help

    private var helpCommands: some Commands {
        CommandGroup(replacing: .help) {
            Button("Report an Issue…") { NSWorkspace.shared.open(Self.issuesURL) }
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension Bucket {
    var shortcutKey: Character {
        switch self {
        case .homebrew: "1"
        case .node: "2"
        case .ruby: "3"
        case .rust: "4"
        case .python: "5"
        }
    }
}
