import DevHubCore
import SwiftUI

struct StandardPackagesView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var tool: Bucket
    @State private var checks: [Bucket: Check] = [:]
    @State private var checkGroups: [Bucket: String] = [:]
    @State private var draft = ""
    @State private var draftKind = PackageKind.npmGlobal
    @State private var notAdded: [String] = []
    @State private var fillRequest: FillRequest?
    @State private var notice: String?

    init(initialTool: Bucket = .node, notice: String? = nil) {
        _tool = State(initialValue: initialTool)
        _notice = State(initialValue: notice)
    }

    private struct Check {
        var group: String?
        var results: [String: PackageResolution]
        var isRunning: Bool
    }

    private struct FillRequest: Identifiable {
        let group: String?
        let entries: [StandardEntry]
        var id: String { group ?? "-" }
    }

    private enum Columns {
        static let kind: CGFloat = 84
        static let newest: CGFloat = 78
        static let installs: CGFloat = 86
        static let remove: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Divider()
            if let notice {
                noticeBar(notice)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    packagesSection
                    targetsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            Divider()
            footer
        }
        .frame(width: 780, height: 700)
        .onAppear { startOnAnEnabledTool() }
        .onChange(of: tool) { draftKind = kinds[0] }
        .confirmationDialog(
            "Replace the list?",
            isPresented: Binding(get: { fillRequest != nil }, set: { if !$0 { fillRequest = nil } }),
            titleVisibility: .visible,
            presenting: fillRequest
        ) { request in
            Button("Replace") { fill(with: request.entries) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("The list will be replaced by the packages installed in \(label(for: StandardTarget(bucket: tool, group: request.group))).")
        }
    }

    // MARK: Data

    private var entries: [StandardEntry] { settings.values.standardPackages.entries(for: tool) }
    private var statuses: [StandardTargetStatus] { state.standardStatus(for: tool) }
    private var kinds: [PackageKind] { StandardPackageLists.allowedKinds(for: tool) }
    private var check: Check? { checks[tool] }

    private var checkOptions: [StandardTarget] {
        let targets = statuses.map(\.target)
        return tool == .python ? targets : targets.filter(\.isVersion)
    }

    private var checkGroup: String? {
        checkGroups[tool] ?? checkOptions.first?.group
    }

    private func startOnAnEnabledTool() {
        let enabled = state.enabledBuckets
        if !enabled.contains(tool), let first = enabled.first { tool = first }
        draftKind = kinds[0]
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Standard packages").font(.system(size: 17, weight: .semibold))
            Text("Installed into a version or manager you choose, or offered when a new Node or Ruby version appears.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func noticeBar(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.green).accessibilityHidden(true)
            Text(verbatim: text).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { notice = nil }
                .buttonStyle(.borderless)
                .clickable()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(state.enabledBuckets, id: \.self) { bucket in
                Button { tool = bucket } label: {
                    VStack(spacing: 3) {
                        Image(bucket.tabIcon).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text(verbatim: bucket.displayName).font(.system(size: 11, weight: tool == bucket ? .semibold : .regular))
                    }
                    .frame(minWidth: 70)
                    .padding(.vertical, 5)
                    .background(tool == bucket ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityAddTraits(tool == bucket ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    // MARK: Packages

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Packages").textCase(.uppercase).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                columnHeader
                ForEach(entries) { entry in
                    Divider()
                    EntryRow(
                        entry: entry,
                        state: rowState(for: entry),
                        showsKind: kinds.count > 1,
                        runtime: runtimeName,
                        source: sourceName,
                        remove: { settings.values.standardPackages.remove(entry, from: tool) }
                    )
                }
                if entries.isEmpty {
                    Divider()
                    Text("No packages yet. Add a name or fill the list from a version.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                Divider()
                addRow
            }
            .card()
            if !notAdded.isEmpty {
                Text("Not added: \(notAdded.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            if kinds.count > 1 { Text("Kind").frame(width: Columns.kind, alignment: .leading) }
            Text("Newest").frame(width: Columns.newest, alignment: .leading)
            Text("To install").frame(width: Columns.installs, alignment: .leading)
            Text("Status").frame(width: 130, alignment: .leading)
            Color.clear.frame(width: Columns.remove, height: 1)
        }
        .textCase(.uppercase)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Name, or several separated by commas", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { add() }
            if kinds.count > 1 {
                Picker("Kind", selection: $draftKind) {
                    ForEach(kinds, id: \.self) { Text($0.singularTitle).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .clickable()
            }
            Button("Add") { add() }
                .clickable()
                .disabled(StandardName.names(in: draft).isEmpty)
            Menu("Fill from…") {
                ForEach(fillOptions) { option in
                    Button { askToFill(option) } label: { label(for: option.target) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .clickable()
            .disabled(fillOptions.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private struct FillOption: Identifiable {
        let target: StandardTarget
        let entries: [StandardEntry]
        var id: String { target.id }
    }

    private var fillOptions: [FillOption] {
        statuses.compactMap { status in
            let found = state.standardFillEntries(bucket: tool, group: status.target.group)
            return found.isEmpty ? nil : FillOption(target: status.target, entries: found)
        }
    }

    private func add() {
        let names = StandardName.names(in: draft)
        guard !names.isEmpty else { return }
        notAdded = settings.values.standardPackages.add(names, kind: draftKind, to: tool)
        draft = ""
    }

    private func askToFill(_ option: FillOption) {
        if entries.isEmpty {
            fill(with: option.entries)
        } else {
            fillRequest = FillRequest(group: option.target.group, entries: option.entries)
        }
    }

    private func fill(with filled: [StandardEntry]) {
        notAdded = []
        settings.values.standardPackages.set(filled, for: tool)
    }

    private func rowState(for entry: StandardEntry) -> EntryRow.RowState {
        guard let check else { return .notChecked }
        if let result = check.results[entry.id] { return .resolved(result) }
        return check.isRunning ? .checking : .notChecked
    }

    private var runtimeName: String {
        switch tool {
        case .node, .ruby: tool.displayName
        case .homebrew, .rust, .python: ""
        }
    }

    private var sourceName: String {
        switch tool {
        case .homebrew: "Homebrew"
        case .node: "npm"
        case .ruby: "RubyGems"
        case .rust: "crates.io"
        case .python: "PyPI"
        }
    }

    // MARK: Install into

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Install into").textCase(.uppercase).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { Divider() }
                    targetRow(status)
                }
                if statuses.isEmpty {
                    Text("Nothing is installed here yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .card()
            notes
        }
    }

    private func targetRow(_ status: StandardTargetStatus) -> some View {
        HStack(spacing: 12) {
            label(for: status.target).fontWeight(.semibold)
            if isDismissed(status.target) {
                Text("Offer dismissed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
            }
            Text("\(status.installed) of \(status.total) installed")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            targetAction(status)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func targetAction(_ status: StandardTargetStatus) -> some View {
        if let session = installing(status.target) {
            ProgressView().controlSize(.small)
            Text("Installing \(session.finishedCount) of \(session.items.count)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Cancel") { state.cancelUpdate() }
                .controlSize(.small)
                .clickable()
        } else if status.isComplete {
            Label("Complete", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        } else if status.total > 0 {
            Button("Install missing") { state.startInstallStandard(bucket: tool, group: status.target.group) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clickable()
                .disabled(state.isBusy || !state.readyBuckets.contains(tool))
        }
    }

    private func installing(_ target: StandardTarget) -> UpdateSession? {
        guard let session = state.session, session.isRunning, session.action == .install,
              let first = session.items.first?.package, first.bucket == target.bucket, first.group == target.group else { return nil }
        return session
    }

    private func isDismissed(_ target: StandardTarget) -> Bool {
        guard let version = target.group, target.isVersion else { return false }
        return state.isStandardOfferDismissed(bucket: target.bucket, version: version)
    }

    private func label(for target: StandardTarget) -> Text {
        guard let group = target.group else { return Text("This Mac") }
        switch target.bucket {
        case .node where target.isVersion, .ruby: return Text(verbatim: "\(target.bucket.displayName) \(group)")
        default: return Text(verbatim: group)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 3) {
            if tool == .homebrew {
                Text("Some casks ask for a password and fail without one.")
            }
            Text("Packages that were not found are skipped.")
            if state.session?.action == .install, state.session?.isRunning == true {
                Text("Progress also shows in the window behind this one.")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if checkOptions.count > 1 {
                Text("Check against").font(.system(size: 12)).foregroundStyle(.secondary)
                Picker("Check against", selection: Binding(get: { checkGroup }, set: { checkGroups[tool] = $0 })) {
                    ForEach(checkOptions) { option in
                        label(for: option).tag(option.group)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .clickable()
            }
            Button("Validate") { validate() }
                .clickable()
                .disabled(entries.isEmpty || check?.isRunning == true || state.isBusy)
            summary
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .clickable()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var summary: some View {
        if check?.isRunning == true {
            ProgressView().controlSize(.small)
            Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let check, !check.results.isEmpty {
            Text(verbatim: summaryText(of: check)).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func summaryText(of check: Check) -> String {
        let results = entries.compactMap { check.results[$0.id] }
        let notFound = results.filter { $0 == .notFound }.count
        let older = results.filter { if case .older = $0 { true } else { false } }.count
        let incompatible = results.filter { if case .incompatible = $0 { true } else { false } }.count
        let unavailable = results.filter { $0 == .unavailable }.count
        var parts: [String] = []
        if notFound > 0 { parts.append(String(localized: "Not found: \(notFound)")) }
        if incompatible > 0 { parts.append(String(localized: "Not compatible: \(incompatible)")) }
        if older > 0 { parts.append(String(localized: "Older version: \(older)")) }
        if unavailable > 0 { parts.append(String(localized: "Could not check: \(unavailable)")) }
        return parts.isEmpty ? String(localized: "All available") : parts.joined(separator: " · ")
    }

    private func validate() {
        let bucket = tool
        let group = checkGroup
        checks[bucket] = Check(group: group, results: [:], isRunning: true)
        Task {
            let results = await state.validateStandard(bucket: bucket, group: group)
            checks[bucket] = Check(group: group, results: results, isRunning: false)
        }
    }
}

// MARK: Rows

private struct EntryRow: View {
    enum RowState {
        case notChecked
        case checking
        case resolved(PackageResolution)
    }

    let entry: StandardEntry
    let state: RowState
    let showsKind: Bool
    let runtime: String
    let source: String
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: entry.name)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsKind {
                Text(entry.kind.singularTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
            }
            Text(verbatim: newest).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(verbatim: installs).font(.system(size: 12, design: .monospaced)).frame(width: 86, alignment: .leading)
            status.frame(width: 130, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .clickable()
            .frame(width: 22)
            .accessibilityLabel("Remove \(entry.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var resolution: PackageResolution? {
        if case let .resolved(resolution) = state { resolution } else { nil }
    }

    private var newest: String {
        switch resolution {
        case let .current(version)?: version
        case let .older(newest, _)?: newest
        case let .incompatible(newest)?: newest
        default: "–"
        }
    }

    private var installs: String {
        resolution?.installVersion ?? "–"
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch state {
            case .notChecked:
                Text("Not checked").font(.system(size: 12)).foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            case let .resolved(resolution):
                resolved(resolution)
            }
        }
    }

    @ViewBuilder
    private func resolved(_ resolution: PackageResolution) -> some View {
        switch resolution {
        case .current:
            chip(Text("OK"), symbol: "checkmark.circle", color: .green)
        case let .older(newest, _):
            chip(Text("Older version"), symbol: "exclamationmark.circle", color: .orange)
            note(Text("\(newest) needs a newer \(runtime)"))
        case .incompatible:
            chip(Text("Not compatible"), symbol: "exclamationmark.circle", color: .red)
            note(Text("No version of it supports this \(runtime) version"))
        case .notFound:
            chip(Text("Not found"), symbol: "exclamationmark.circle", color: .red)
            note(entry.kind == .rustToolchain ? Text("Not a toolchain name") : Text("No such package on \(source)"))
        case .unavailable:
            chip(Text("Could not check"), symbol: "exclamationmark.circle", color: .secondary)
        }
    }

    private func chip(_ title: Text, symbol: String, color: Color) -> some View {
        Label { title } icon: { Image(systemName: symbol) }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private func note(_ text: Text) -> some View {
        text.font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func card() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
