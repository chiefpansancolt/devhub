import SwiftUI

@main
struct DevHubApp: App {
    var body: some Scene {
        MenuBarExtra("DevHub", image: "MenuBarUpToDate") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)

        Window("DevHub", id: MainWindow.id) {
            MainWindowView()
        }
        .defaultSize(width: 1180, height: 760)
    }
}

enum MainWindow {
    static let id = "main"
}
