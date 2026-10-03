import DevHubCore
import SwiftUI

enum Columns {
    static let checkbox: CGFloat = 18
    static let kind: CGFloat = 96
    static let version: CGFloat = 84
    static let actions: CGFloat = 132
}

struct PackageBrowserView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings
    let ui: WindowUIState
    @FocusState private var searchIsFocused: Bool
    @FocusState private var listIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            StandardPackagesBanners()
            modeBar
            Divider()
            content
            UpdateProgressStrip()
            if settings.values.showOutputLog {
                OutputLogView()
            }
        }
        .onChange(of: ui.searchFocusRequest) {
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                searchIsFocused = true
            }
        }
        .confirmationDialog(
            "Update \(outdatedInScope.count) packages?",
            isPresented: Binding(get: { ui.isConfirmingUpdateAll }, set: { ui.isConfirmingUpdateAll = $0 }),
            titleVisibility: .visible
        ) {
            Button("Update \(outdatedInScope.count)") { state.startUpdate(outdatedInScope) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each package is updated one at a time. This can take a while.")
        }
    }

    // MARK: Data

    private var scopePackages: [InstalledPackage] { state.packages(in: ui.scope) }
    private var outdatedInScope: [InstalledPackage] { state.outdated(in: ui.scope) }
    private var rows: [InstalledPackage] { PackageListing.rows(from: scopePackages, mode: ui.mode, search: ui.search) }

    private var checkedPackages: [InstalledPackage] {
        outdatedInScope.filter { ui.checkedIDs.contains($0.id) }
    }

    private var title: Text {
        let bucketName = Text(verbatim: ui.scope.bucket.displayName)
        guard let group = ui.scope.group else { return bucketName }
        if ui.scope.bucket.groupsByKind, let kind = PackageKind(rawValue: group) {
            return bucketName + Text(verbatim: " · ") + Text(kind.pluralTitle)
        }
        return bucketName + Text(verbatim: " · \(group)")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            BucketBadge(bucket: ui.scope.bucket, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.system(size: 17, weight: .semibold))
                subtitle.font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                state.startRefresh()
            } label: {
                if state.isChecking { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .clickable()
            .disabled(state.isChecking || state.isBusy)
            .accessibilityLabel("Check again")

            Button("Update selected (\(checkedPackages.count))") { state.startUpdate(checkedPackages) }
                .clickable()
                .disabled(checkedPackages.isEmpty || state.isBusy)
            Button("Update all") {
                if settings.values.confirmUpdateAll {
                    ui.isConfirmingUpdateAll = true
                } else {
                    state.startUpdate(outdatedInScope)
                }
            }
                .buttonStyle(.borderedProminent)
                .clickable()
                .disabled(outdatedInScope.isEmpty || state.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var subtitle: some View {
        if state.hasChecked {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { counts; Text("·"); CheckedAgoText(date: state.lastChecked) }
                VStack(alignment: .leading, spacing: 1) { counts; CheckedAgoText(date: state.lastChecked) }
            }
        } else {
            Text("Checking…")
        }
    }

    private var counts: some View {
        (Text("\(scopePackages.count) installed") + Text(verbatim: " · ") + Text("\(outdatedInScope.count) updates available"))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Mode bar

    private var modeBar: some View {
        HStack(spacing: 12) {
            Picker("List", selection: Binding(get: { ui.mode }, set: { ui.mode = $0 })) {
                Text("Updates (\(outdatedInScope.count))").tag(PackageListMode.updates)
                Text("All installed (\(scopePackages.count))").tag(PackageListMode.allInstalled)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .clickable()

            Spacer()

            if ui.mode == .allInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Filter installed", text: Binding(get: { ui.search }, set: { ui.search = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchIsFocused)
                        .accessibilityLabel("Filter installed packages")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 200)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .clickable()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let problem = state.setupProblems[ui.scope.bucket] {
            EmptyMessage(
                symbol: "wrench.and.screwdriver",
                title: Text("\(ui.scope.bucket.displayName) is not set up"),
                detail: Text(problem),
                actionTitle: "Open Settings"
            ) {
                settings.selectedTab = ui.scope.bucket.settingsTab
                openSettings()
                AppActivation.bringToFront()
            }
        } else if !state.hasChecked {
            EmptyMessage(symbol: nil, title: Text("Checking for updates"), detail: nil)
        } else if rows.isEmpty {
            emptyList
        } else {
            list
        }
    }

    @ViewBuilder
    private var emptyList: some View {
        if ui.mode == .updates {
            EmptyMessage(symbol: "checkmark.circle", title: Text("Everything here is up to date"), detail: Text("Switch to All installed to see every package."))
        } else if !ui.search.isEmpty {
            EmptyMessage(symbol: "magnifyingglass", title: Text("No packages match “\(ui.search)”"), detail: nil)
        } else {
            EmptyMessage(symbol: "shippingbox", title: Text("Nothing is installed here"), detail: nil)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(state.issues(in: ui.scope.bucket)) { issue in
                        IssueBanner(issue: issue)
                    }
                    Section {
                        ForEach(rows) { package in
                            PackageRowView(package: package, ui: ui)
                        }
                    } header: {
                        ColumnHeader(bucket: ui.scope.bucket, rows: rows, ui: ui)
                    }
                }
            }
            .focusable()
            .focused($listIsFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(by: 1, proxy) }
            .onKeyPress(.upArrow) { moveSelection(by: -1, proxy) }
            .onKeyPress(.escape) {
                guard ui.inspectedID != nil else { return .ignored }
                ui.closeInspector()
                return .handled
            }
            .onChange(of: ui.inspectedID) { listIsFocused = true }
        }
    }

    private func moveSelection(by step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == ui.inspectedID }
        let start = current ?? (step > 0 ? -1 : rows.count)
        let next = min(max(start + step, 0), rows.count - 1)
        ui.isConfirmingUninstall = false
        ui.inspectedID = rows[next].id
        proxy.scrollTo(rows[next].id)
        return .handled
    }
}

private struct ColumnHeader: View {
    let bucket: Bucket
    let rows: [InstalledPackage]
    let ui: WindowUIState

    var body: some View {
        let outdated = rows.filter(\.isOutdated)
        HStack(spacing: 12) {
            Toggle("Select all", isOn: Binding(
                get: { !outdated.isEmpty && outdated.allSatisfy { ui.checkedIDs.contains($0.id) } },
                set: { isOn in
                    if isOn { ui.checkedIDs.formUnion(outdated.map(\.id)) } else { ui.checkedIDs.subtract(outdated.map(\.id)) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .clickable()
            .disabled(outdated.isEmpty)
            .frame(width: Columns.checkbox)

            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text(kindTitle).frame(width: Columns.kind, alignment: .leading)
            Text("Installed").frame(width: Columns.version, alignment: .leading)
            Text("Latest").frame(width: Columns.version, alignment: .leading)
            Color.clear.frame(width: Columns.actions, height: 1)
        }
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var kindTitle: LocalizedStringKey {
        switch bucket {
        case .homebrew: "Type"
        case .node: "Version or manager"
        case .ruby: "Ruby version"
        case .rust: "Type"
        case .python: "Manager"
        }
    }
}

private struct IssueBanner: View {
    let issue: ScanIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(issue.group.map { "\($0): \(issue.message)" } ?? issue.message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

struct EmptyMessage: View {
    let symbol: String?
    let title: Text
    let detail: Text?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            } else {
                ProgressView()
            }
            title.font(.system(size: 15, weight: .semibold))
            detail?.font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .clickable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
