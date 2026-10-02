import AppKit
import DevHubCore
import SwiftUI

private enum HistoryColumns {
    static let time: CGFloat = 92
    static let action: CGFloat = 132
    static let bucket: CGFloat = 100
    static let change: CGFloat = 130
    static let result: CGFloat = 96
}

struct HistoryView: View {
    @Environment(AppState.self) private var state
    let ui: WindowUIState
    @FocusState private var searchIsFocused: Bool
    @FocusState private var listIsFocused: Bool

    private var history: HistoryStore { state.history }

    private var visible: [HistoryEntry] {
        HistoryListing.filter(
            history.entries,
            action: ui.historyFilter,
            range: ui.historyRange,
            bucket: ui.historyBucket,
            search: ui.historySearch,
            now: Date()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            content
            Divider()
            footer
        }
        .onChange(of: ui.searchFocusRequest) { searchIsFocused = true }
        .confirmationDialog(
            "Clear the history?",
            isPresented: Binding(get: { ui.isConfirmingClearHistory }, set: { ui.isConfirmingClearHistory = $0 }),
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                ui.inspectedHistoryID = nil
                Task { await history.clear() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every entry from the history file. Your packages are not changed.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("History").font(.system(size: 17, weight: .semibold))
                Text("\(history.totalCount) entries")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Show log in Finder") { HistoryFileActions.showInFinder(history) }
                .clickable()
            Button("Export…") { HistoryFileActions.export(history) }
                .clickable()
                .disabled(history.totalCount == 0)
            Button("Clear…") { ui.isConfirmingClearHistory = true }
                .foregroundStyle(.red)
                .clickable()
                .disabled(history.totalCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Filters

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                actionPicker
                Spacer()
                rangePicker
                bucketPicker
                searchField.frame(width: 170)
            }
            VStack(alignment: .leading, spacing: 8) {
                actionPicker
                HStack(spacing: 12) {
                    rangePicker
                    bucketPicker
                    searchField.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var actionPicker: some View {
        Picker("Action", selection: Binding(get: { ui.historyFilter }, set: { ui.historyFilter = $0 })) {
            Text("All").tag(HistoryActionFilter.all)
            Text("Updates").tag(HistoryActionFilter.updates)
            Text("Uninstalls").tag(HistoryActionFilter.uninstalls)
            Text("Checks").tag(HistoryActionFilter.checks)
            Text("Failed").tag(HistoryActionFilter.failed)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .clickable()
    }

    private var rangePicker: some View {
        Picker("Date range", selection: Binding(get: { ui.historyRange }, set: { ui.historyRange = $0 })) {
            Text("Last 7 days").tag(HistoryRange.lastSevenDays)
            Text("Today").tag(HistoryRange.today)
            Text("Last 30 days").tag(HistoryRange.lastThirtyDays)
            Text("All time").tag(HistoryRange.allTime)
        }
        .labelsHidden()
        .fixedSize()
        .clickable()
    }

    private var bucketPicker: some View {
        Picker("Bucket", selection: Binding(get: { ui.historyBucket }, set: { ui.historyBucket = $0 })) {
            Text("All buckets").tag(Bucket?.none)
            ForEach(state.enabledBuckets, id: \.self) { bucket in
                Text(bucket.displayName).tag(Bucket?.some(bucket))
            }
        }
        .labelsHidden()
        .fixedSize()
        .clickable()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search history", text: Binding(get: { ui.historySearch }, set: { ui.historySearch = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchIsFocused)
                .accessibilityLabel("Search history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .clickable()
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        let entries = visible
        if history.totalCount == 0 {
            EmptyMessage(
                symbol: "clock.arrow.circlepath",
                title: Text("Nothing has happened yet"),
                detail: Text("Every update, uninstall and check is recorded here with the time it ran and the command used.")
            )
        } else if entries.isEmpty {
            EmptyMessage(symbol: "magnifyingglass", title: Text("No entries match these filters"), detail: nil)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(HistoryListing.days(entries), id: \.day) { day in
                                DayHeader(day: day.day)
                                ForEach(day.entries) { entry in
                                    HistoryRow(entry: entry, ui: ui, showsBucket: showsBucketColumn)
                                }
                            }
                        } header: {
                            columnHeader
                        }
                    }
                }
                .focusable()
                .focused($listIsFocused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { moveSelection(by: 1, in: entries, proxy) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, in: entries, proxy) }
                .onKeyPress(.escape) {
                    guard ui.inspectedHistoryID != nil else { return .ignored }
                    ui.inspectedHistoryID = nil
                    return .handled
                }
                .onChange(of: ui.inspectedHistoryID) { listIsFocused = true }
            }
        }
    }

    private func moveSelection(by step: Int, in entries: [HistoryEntry], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        let current = entries.firstIndex { $0.id == ui.inspectedHistoryID }
        let start = current ?? (step > 0 ? -1 : entries.count)
        let next = min(max(start + step, 0), entries.count - 1)
        ui.inspectedHistoryID = entries[next].id
        proxy.scrollTo(entries[next].id)
        return .handled
    }

    private var showsBucketColumn: Bool { ui.inspectedHistoryID == nil }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("Time").frame(width: HistoryColumns.time, alignment: .leading)
            Text("Action").frame(width: HistoryColumns.action, alignment: .leading)
            Text("Package").frame(maxWidth: .infinity, alignment: .leading)
            if showsBucketColumn {
                Text("Bucket").frame(width: HistoryColumns.bucket, alignment: .leading)
            }
            Text("Change").frame(width: HistoryColumns.change, alignment: .leading)
            Text("Result").frame(width: HistoryColumns.result, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").accessibilityHidden(true)
            Text(history.fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "")
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Text(history.fileSize.formatted(.byteCount(style: .file)))
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

private struct DayHeader: View {
    let day: Date

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
            .overlay(alignment: .bottom) { Divider() }
    }

    private var label: String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let ui: WindowUIState
    let showsBucket: Bool

    var body: some View {
        let isOpen = ui.inspectedHistoryID == entry.id
        Button {
            ui.toggleHistoryEntry(entry)
        } label: {
            HStack(spacing: 12) {
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(width: HistoryColumns.time, alignment: .leading)
                Label(entry.action.title, systemImage: entry.action.symbol)
                    .frame(width: HistoryColumns.action, alignment: .leading)
                Text(entry.package ?? String(localized: "All buckets"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsBucket {
                    bucketCell.frame(width: HistoryColumns.bucket, alignment: .leading)
                }
                Text(entry.changeText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: HistoryColumns.change, alignment: .leading)
                ResultChip(ok: entry.ok).frame(width: HistoryColumns.result, alignment: .leading)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(isOpen ? Color.accentColor.opacity(0.14) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    @ViewBuilder
    private var bucketCell: some View {
        if let bucket = entry.bucket {
            HStack(spacing: 6) {
                BucketBadge(bucket: bucket, size: 14)
                Text(bucket.displayName).foregroundStyle(.secondary)
            }
        } else {
            Text("All").foregroundStyle(.secondary)
        }
    }
}

struct ResultChip: View {
    let ok: Bool

    var body: some View {
        Text(ok ? "Success" : "Failed")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ok ? Color.green : Color.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background((ok ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}

extension HistoryAction {
    var title: LocalizedStringKey {
        switch self {
        case .check: "Checked"
        case .update: "Updated"
        case .uninstall: "Uninstalled"
        }
    }

    var symbol: String {
        switch self {
        case .check: "arrow.clockwise"
        case .update: "arrow.up"
        case .uninstall: "trash"
        }
    }
}

extension HistoryEntry {
    var changeText: String {
        switch action {
        case .check: message ?? ""
        case .update: [fromVersion, toVersion].compactMap { $0 }.joined(separator: " → ")
        case .uninstall: fromVersion ?? ""
        }
    }
}
