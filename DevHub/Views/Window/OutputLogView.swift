import DevHubCore
import SwiftUI

struct OutputLogView: View {
    @Environment(AppState.self) private var state
    @AppStorage("outputLogExpanded") private var isExpanded = true

    private static let background = Color(red: 0.12, green: 0.12, blue: 0.13)
    private static let text = Color(red: 0.85, green: 0.85, blue: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Output")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                    Spacer()
                }
                .foregroundStyle(Color(red: 0.63, green: 0.63, blue: 0.65))
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickable()
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        if state.log.isEmpty {
                            Text("Command output appears here when you update or uninstall a package.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(red: 0.63, green: 0.63, blue: 0.65))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(state.log) { line in
                                    Text(line.entry.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .fontWeight(line.entry.kind == .command ? .semibold : .regular)
                                        .foregroundStyle(color(for: line.entry.kind))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(height: 110)
                    .onChange(of: state.log.last?.id) {
                        if let last = state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Self.background)
        .environment(\.colorScheme, .dark)
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .command: .white
        case .output: Self.text
        case .error: Color(red: 1.0, green: 0.54, blue: 0.5)
        }
    }
}
