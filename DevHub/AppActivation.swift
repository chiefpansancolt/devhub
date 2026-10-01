import AppKit

@MainActor
enum AppActivation {
    // The app starts as a menu bar app with no Dock icon. A menu bar app cannot show its menus or take focus,
    // so it becomes a regular app while the main window is open.
    static func becomeRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func becomeMenuBarApp() {
        NSApp.setActivationPolicy(.accessory)
    }
}
