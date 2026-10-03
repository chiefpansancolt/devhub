import DevHubCore
import SwiftUI

struct WindowView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ui: WindowUIState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(ui: ui)
                .frame(width: 220)
            Divider()
            switch ui.page {
            case .packages where state.enabledBuckets.isEmpty:
                EmptyMessage(
                    symbol: "switch.2",
                    title: Text("All tools are turned off"),
                    detail: Text("Turn on Homebrew, Node or Ruby in Settings."),
                    actionTitle: "Open Settings"
                ) {
                    settings.selectedTab = .general
                    openSettings()
                    AppActivation.bringToFront()
                }
            case .packages: PackageBrowserView(ui: ui)
            case .history: HistoryView(ui: ui)
            }
            if inspectorIsOpen {
                Divider()
                Group {
                    switch ui.page {
                    case .packages: InspectorView(ui: ui)
                    case .history: HistoryInspectorView(ui: ui)
                    }
                }
                .frame(width: 320)
                .background(Color(nsColor: .controlBackgroundColor))
                .transition(.move(edge: .trailing))
            }
        }
        .sheet(item: Binding(get: { ui.sheet }, set: { ui.sheet = $0 })) { sheet in
            switch sheet {
            case let .standardPackages(tool):
                StandardPackagesView(initialTool: tool, notice: ui.standardPackagesNotice)
                    .onAppear { ui.standardPackagesNotice = nil }
            case .exportLists: ExportListsSheet()
            case .importLists: ImportListsSheet(ui: ui)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: inspectorIsOpen)
        .frame(minWidth: inspectorIsOpen ? 1180 : 860, minHeight: 560)
        .onAppear {
            AppActivation.windowOpened()
            keepSelectionOnAToolThatIsOn()
        }
        .onDisappear { AppActivation.windowClosed() }
        .onChange(of: state.enabledBuckets) { keepSelectionOnAToolThatIsOn() }
        .onChange(of: inspectedPackageIsMissing) {
            if inspectedPackageIsMissing { ui.closeInspector() }
        }
        .onChange(of: state.isBusy) {
            if state.isBusy { ui.isConfirmingUninstall = false }
        }
        .onChange(of: state.lastChecked) {
            ui.checkedIDs = ui.checkedIDs.filter { state.package(withID: $0)?.isOutdated == true }
        }
    }

    private func keepSelectionOnAToolThatIsOn() {
        if let filter = ui.historyBucket, !state.enabledBuckets.contains(filter) {
            ui.historyBucket = nil
        }
        guard !state.enabledBuckets.contains(ui.scope.bucket), let first = state.enabledBuckets.first else { return }
        ui.select(PackageScope(bucket: first))
    }

    private var inspectedPackageIsMissing: Bool {
        ui.inspectedID.map { state.package(withID: $0) == nil } ?? false
    }

    private var inspectorIsOpen: Bool {
        switch ui.page {
        case .packages: ui.inspectedID.flatMap { state.package(withID: $0) } != nil
        case .history: ui.inspectedHistoryID.flatMap { id in state.history.entries.first { $0.id == id } } != nil
        }
    }
}
