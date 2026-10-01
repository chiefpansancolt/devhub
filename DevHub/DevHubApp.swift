import DevHubCore
import SwiftUI

@main
struct DevHubApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState(toolchain: .detect())
        state.startScheduledChecks()
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
        } label: {
            MenuBarLabel(icon: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("DevHub", id: MainWindow.id) {
            MainWindowView()
                .environment(appState)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

enum MainWindow {
    static let id = "main"
}
