import DevHubCore
import SwiftUI

struct WindowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ui = WindowUIState()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(ui: ui)
                .frame(width: 220)
            Divider()
            PackageBrowserView(ui: ui)
            if inspectorIsOpen {
                Divider()
                InspectorView(ui: ui)
                    .frame(width: 320)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: inspectorIsOpen)
        .frame(minWidth: 960, minHeight: 560)
        .onAppear { AppActivation.becomeRegularApp() }
        .onDisappear { AppActivation.becomeMenuBarApp() }
        .onChange(of: state.lastChecked) {
            ui.checkedIDs = ui.checkedIDs.filter { state.package(withID: $0)?.isOutdated == true }
        }
    }

    private var inspectorIsOpen: Bool {
        ui.inspectedID.flatMap { state.package(withID: $0) } != nil
    }
}
