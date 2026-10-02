import DevHubCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    let ui: WindowUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Buckets")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 2) {
                    if state.enabledBuckets.isEmpty {
                        Text("All tools are turned off. Turn them on in Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    ForEach(state.enabledBuckets, id: \.self) { bucket in
                        BucketRow(bucket: bucket, ui: ui)
                        if ui.expandedBuckets.contains(bucket), state.setupProblems[bucket] == nil {
                            ForEach(childScopes(of: bucket), id: \.self) { scope in
                                ChildRow(scope: scope, ui: ui)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Text("Activity")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
            HistoryRow(ui: ui)
                .padding(.horizontal, 10)

            Text("Bucket numbers show available updates. Sub-rows show updates of installed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            Divider()
            Button {
                openSettings()
                AppActivation.bringToFront()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .clickable()
            .handCursorOnHover()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private func childScopes(of bucket: Bucket) -> [PackageScope] {
        [PackageScope(bucket: bucket)] + state.groupScopes(of: bucket)
    }
}

private struct BucketRow: View {
    @Environment(AppState.self) private var state
    let bucket: Bucket
    let ui: WindowUIState

    var body: some View {
        let problem = state.setupProblems[bucket]
        let isExpanded = ui.expandedBuckets.contains(bucket)
        // A bucket that is not set up has no rows to pick, so its header selects it to show the reason.
        let isSelected = problem != nil && ui.page == .packages && ui.scope.bucket == bucket
        Button {
            if problem != nil {
                ui.select(PackageScope(bucket: bucket))
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { ui.toggleExpanded(bucket) }
            }
        } label: {
            HStack(spacing: 8) {
                BucketBadge(bucket: bucket, size: 18)
                Text(bucket.displayName).font(.system(size: 13, weight: .semibold))
                Spacer()
                if problem != nil {
                    Text("Not set up").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("\(state.outdated(in: bucket).count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .handCursorOnHover()
        .accessibilityValue(problem != nil ? Text("") : (isExpanded ? Text("Expanded") : Text("Collapsed")))
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var state
    let ui: WindowUIState

    var body: some View {
        let isSelected = ui.page == .history
        Button {
            ui.showHistory()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("History").font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .handCursorOnHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChildRow: View {
    @Environment(AppState.self) private var state
    let scope: PackageScope
    let ui: WindowUIState

    var body: some View {
        let isSelected = ui.page == .packages && ui.scope == scope
        Button {
            ui.select(scope)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(state.outdated(in: scope).count) of \(state.packages(in: scope).count)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 30)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .handCursorOnHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: LocalizedStringKey {
        guard let group = scope.group else {
            return scope.bucket.groupsByVersion ? "All versions" : "All packages"
        }
        if scope.bucket.groupsByKind, let kind = PackageKind(rawValue: group) {
            return kind.pluralTitle
        }
        return LocalizedStringKey(group)
    }
}
