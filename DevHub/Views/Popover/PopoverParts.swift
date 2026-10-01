import DevHubCore
import SwiftUI

struct PopoverHeader<Trailing: View>: View {
    let title: Text
    let subtitle: Text?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 15, weight: .semibold))
                subtitle?.font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct CheckedAgoText: View {
    let date: Date?

    var body: some View {
        if let date {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if context.date.timeIntervalSince(date) < 60 {
                    Text("Checked just now")
                } else {
                    Text("Checked \(Text(date, format: .relative(presentation: .numeric, unitsStyle: .wide)))")
                }
            }
        }
    }
}

struct NextCheckText: View {
    let date: Date?

    var body: some View {
        if let date {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let remaining = date.timeIntervalSince(context.date)
                if remaining < 60 {
                    Text("Next check soon")
                } else {
                    Text("Next check in \(Self.formatter.string(from: remaining) ?? "")")
                }
            }
        }
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct NotSetUpRow: View {
    let bucket: Bucket
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BucketBadge(bucket: bucket).opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bucket.displayName) is not set up").font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct PopoverFooter: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            if state.popoverMode == .updating {
                Text("Updating packages").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { state.cancelUpdate() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .clickable()
            } else {
                Button {
                    state.startRefresh()
                } label: {
                    if state.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(state.isChecking)
                .clickable()
                .accessibilityLabel("Check again")

                Group {
                    if state.isChecking {
                        Text("Checking")
                    } else {
                        NextCheckText(date: state.nextCheck)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Open window") {
                    openWindow(id: MainWindow.id)
                    AppActivation.becomeRegularApp()
                }
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
                .clickable()

                Menu {
                    Button("Quit DevHub") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .clickable()
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
