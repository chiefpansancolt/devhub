import DevHubCore
import SwiftUI

struct CheckingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: Text("Checking for updates"),
                subtitle: Text(state.readyBuckets.map(\.displayName).formatted(.list(type: .and, width: .narrow)))
            ) {
                ProgressView().controlSize(.small)
            }
            Divider()
            VStack(spacing: 0) {
                ForEach(state.readyBuckets, id: \.self) { _ in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 28, height: 28)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                ForEach(Bucket.allCases.filter { state.setupProblems[$0] != nil }, id: \.self) { bucket in
                    NotSetUpRow(bucket: bucket, message: state.setupProblems[bucket] ?? "")
                }
            }
            .accessibilityHidden(true)
        }
    }
}
