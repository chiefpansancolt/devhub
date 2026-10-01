import DevHubCore
import SwiftUI

struct UpdatesView: View {
    @Environment(AppState.self) private var state
    @Environment(SettingsStore.self) private var settings
    @State private var expanded: Set<Bucket> = []
    @State private var hasChosenDefaultExpansion = false
    @State private var isConfirmingUpdateAll = false

    private static let maxListHeight: CGFloat = 420
    private static let smallBucketLimit = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FittingScrollView(maxHeight: Self.maxListHeight) {
                VStack(spacing: 0) {
                    ForEach(Bucket.allCases, id: \.self) { bucket in
                        BucketSection(bucket: bucket, isExpanded: binding(for: bucket))
                        if bucket != Bucket.allCases.last { Divider().padding(.leading, 54) }
                    }
                }
            }
        }
        .onAppear(perform: expandSmallBuckets)
        .onChange(of: state.lastChecked) { expandSmallBuckets() }
    }

    private var header: some View {
        PopoverHeader(title: Text("^[\(state.totalOutdated) update](inflect: true) available")) {
            if isConfirmingUpdateAll {
                Text("Updates run one package at a time in each bucket.")
            } else {
                CheckedAgoText(date: state.lastChecked)
            }
        } trailing: {
            if isConfirmingUpdateAll {
                HStack(spacing: 6) {
                    Button("Cancel") { isConfirmingUpdateAll = false }
                        .clickable()
                    Button("Update \(state.totalOutdated)") {
                        isConfirmingUpdateAll = false
                        state.startUpdateAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .clickable()
                }
                .controlSize(.small)
            } else {
                Button("Update all") {
                    if settings.values.confirmUpdateAll {
                        isConfirmingUpdateAll = true
                    } else {
                        state.startUpdateAll()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .clickable()
            }
        }
    }

    private func binding(for bucket: Bucket) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(bucket) },
            set: { isOn in
                if isOn { expanded.insert(bucket) } else { expanded.remove(bucket) }
            }
        )
    }

    // A bucket with a long list starts collapsed so the popover stays short. The user can open it.
    private func expandSmallBuckets() {
        guard !hasChosenDefaultExpansion else { return }
        hasChosenDefaultExpansion = true
        expanded = Set(Bucket.allCases.filter {
            let count = state.outdated(in: $0).count
            return count > 0 && count <= Self.smallBucketLimit
        })
    }
}

struct BucketSection: View {
    let bucket: Bucket
    @Binding var isExpanded: Bool
    @Environment(AppState.self) private var state

    var body: some View {
        if let problem = state.setupProblems[bucket] {
            NotSetUpRow(bucket: bucket, message: problem)
        } else {
            let outdated = state.outdated(in: bucket)
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        BucketBadge(bucket: bucket)
                        Text(bucket.displayName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if outdated.isEmpty {
                            Text("Up to date").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            CountPill(count: outdated.count)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(outdated.isEmpty)
                .clickable()
                .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

                if isExpanded {
                    ForEach(state.issues(in: bucket)) { issue in
                        IssueRow(issue: issue)
                    }
                    let groups = state.outdatedGroups(in: bucket)
                    ForEach(groups.indices, id: \.self) { index in
                        if let group = groups[index].group {
                            Text("\(bucket.displayName) \(group)")
                                .font(.system(size: 11, weight: .semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 54)
                                .padding(.top, 4)
                        }
                        ForEach(groups[index].packages) { package in
                            PackageRow(package: package)
                        }
                    }
                }
            }
        }
    }
}

struct IssueRow: View {
    let issue: ScanIssue

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(issue.group.map { "\($0): \(issue.message)" } ?? issue.message)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.system(size: 11))
        .padding(.leading, 54)
        .padding(.trailing, 16)
        .padding(.vertical, 3)
    }
}

struct PackageRow: View {
    let package: InstalledPackage
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(package.name).font(.system(size: 13)).lineLimit(1)
                    if package.kind == .cask {
                        Text("cask").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text("\(package.installedVersion) → \(package.availableUpdate ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Update") { state.startUpdate([package]) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clickable()
                .accessibilityLabel("Update \(package.name)")
        }
        .padding(.leading, 54)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }
}
