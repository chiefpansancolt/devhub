import DevHubCore
import SwiftUI
import UserNotifications

@main
struct DevHubApp: App {
    @State private var settings: SettingsStore
    @State private var appState: AppState
    @State private var windowUI = WindowUIState()
    private let effects = AppEffects()

    init() {
        let settings = SettingsStore()
        let state = AppState(settings: settings.values, notifier: SystemNotifier(), notificationLedger: NotificationLedger())
        UNUserNotificationCenter.current().delegate = effects.notificationDelegate

        AppEffects.launchLanguage = settings.values.language
        AppEffects.apply(language: settings.values.language)
        AppEffects.apply(theme: settings.values.theme)
        settings.onChange = { [weak state] old, new in
            state?.apply(new)
            if old.theme != new.theme { AppEffects.apply(theme: new.theme) }
            if old.language != new.language { AppEffects.apply(language: new.language) }
        }
        effects.watchForWake { [weak state] in
            if settings.values.checkOnWake { state?.checkAfterWake() }
        }

        Task { await state.history.startUp() }
        state.startScheduledChecks(checkNow: settings.values.checkOnLaunch)

        _settings = State(initialValue: settings)
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
                .environment(settings)
        } label: {
            MenuBarLabel(icon: appState.menuBarIcon, style: settings.values.menuBarIconStyle)
        }
        .menuBarExtraStyle(.window)

        Window("DevHub", id: MainWindow.id) {
            WindowView(ui: windowUI)
                .environment(appState)
                .environment(settings)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            DevHubCommands(state: appState, settings: settings, ui: windowUI)
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(settings)
        }
    }
}

enum MainWindow {
    static let id = "main"
}
