import AppKit
import DevHubCore

/// The parts of the settings that act on the app itself instead of on a screen.
@MainActor
final class AppEffects {
    private var wakeObserver: NSObjectProtocol?

    static func apply(theme: AppTheme) {
        switch theme {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Calls `perform` after the Mac wakes from sleep.
    func watchForWake(perform: @escaping @MainActor () -> Void) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { perform() }
        }
    }
}
