import AppKit

@MainActor
enum AppActivation {
    private static var openWindows = 0

    // The app starts as a menu bar app with no Dock icon. A menu bar app cannot show its menus or take focus,
    // so it becomes a regular app while the main window or the Settings window is open.
    static func windowOpened() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func bringToFront() {
        NSApp.activate()
    }

    /// Closes the menu bar popover. Call it before a button in the popover opens a window, so the popover does not stay over it.
    static func dismissMenuBarPopover() {
        let popover = NSApp.keyWindow as? NSPanel ?? NSApp.windows.first { $0 is NSPanel && $0.isVisible }
        popover?.close()
    }
}
