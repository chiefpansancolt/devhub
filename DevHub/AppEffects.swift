import AppKit
import DevHubCore

/// The parts of the settings that act on the app itself instead of on a screen.
@MainActor
final class AppEffects {
    /// Set by a view that can open the main window. A clicked notification calls it.
    static var openMainWindow: (@MainActor () -> Void)?

    /// The language setting when DevHub started. A different setting needs a restart.
    static var launchLanguage: String?

    let notificationDelegate = NotificationDelegate()
    private var wakeObserver: NSObjectProtocol?

    // macOS reads an app's languages when it starts, so the choice is saved for the next start.
    static func apply(language: String?) {
        if let language {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

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
