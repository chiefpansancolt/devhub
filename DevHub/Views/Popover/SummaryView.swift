import DevHubCore
import SwiftUI

struct SummaryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let session = state.session {
            VStack(spacing: 0) {
                PopoverHeader(title: session.resultTitle) {
                    if session.failedCount > 0, session.skippedCount > 0 {
                        Text("\(session.skippedCount) skipped")
                    }
                } trailing: {
                    Button("Done") { state.dismissSession() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .clickable()
                }
                Divider()
                FittingScrollView(maxHeight: 260) {
                    VStack(spacing: 0) {
                        ForEach(session.failedItems) { item in
                            FailedRow(item: item)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                if session.failedCount > 0 {
                    Divider()
                    HStack {
                        Button("Try again") { state.retryFailed() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .clickable()
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

}

extension UpdateSession {
    var resultTitle: Text {
        if failedCount > 0 {
            Text("\(doneCount) updated, \(failedCount) failed")
        } else {
            Text("\(doneCount) updated, \(skippedCount) skipped")
        }
    }
}

struct FailedRow: View {
    let item: UpdateItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.package.name).font(.system(size: 13, weight: .semibold))
                if case let .failed(message) = item.status {
                    Text(message).font(.system(size: 12)).foregroundStyle(.red).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
