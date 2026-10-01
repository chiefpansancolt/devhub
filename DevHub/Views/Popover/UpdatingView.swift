import DevHubCore
import SwiftUI

struct UpdatingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let session = state.session {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updating packages").font(.system(size: 15, weight: .semibold))
                        Text("\(session.finishedCount) of \(session.items.count) done")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(session.finishedCount), total: Double(session.items.count))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                Divider()
                FittingScrollView(maxHeight: 260) {
                    VStack(spacing: 0) {
                        ForEach(session.items) { item in
                            UpdateStatusRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct UpdateStatusRow: View {
    let item: UpdateItem

    var body: some View {
        HStack(spacing: 10) {
            Text(item.package.name).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 8)
            statusView
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .waiting:
            Text("Waiting").font(.system(size: 12)).foregroundStyle(.secondary)
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .done:
            Label("Done", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark").font(.system(size: 12)).foregroundStyle(.red)
        case .skipped:
            Text("Skipped").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
