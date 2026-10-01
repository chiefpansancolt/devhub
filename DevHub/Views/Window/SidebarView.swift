import DevHubCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
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
                    ForEach(Bucket.allCases, id: \.self) { bucket in
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

            Text("Bucket numbers show available updates. Sub-rows show updates of installed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
        let isSelected = problem != nil && ui.scope.bucket == bucket
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .accessibilityValue(problem != nil ? Text("") : (isExpanded ? Text("Expanded") : Text("Collapsed")))
    }
}

private struct ChildRow: View {
    @Environment(AppState.self) private var state
    let scope: PackageScope
    let ui: WindowUIState

    var body: some View {
        let isSelected = ui.scope == scope
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
    }

    private var title: LocalizedStringKey {
        guard let group = scope.group else {
            return scope.bucket == .homebrew ? "All packages" : "All versions"
        }
        if scope.bucket == .homebrew {
            return group == PackageKind.cask.rawValue ? "Casks" : "Formulae"
        }
        return LocalizedStringKey(group)
    }
}
