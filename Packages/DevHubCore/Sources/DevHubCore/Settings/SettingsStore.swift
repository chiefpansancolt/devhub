import Foundation
import Observation

public enum SettingsTab: String, Sendable, CaseIterable {
    case general
    case appearance
    case homebrew
    case node
    case ruby
    case rust
    case python
    case history
}

@MainActor
@Observable
public final class SettingsStore {
    private static let key = "settings.v1"

    public var values: SettingsValues {
        didSet {
            save()
            onChange?(oldValue, values)
        }
    }

    @ObservationIgnored public var onChange: (@MainActor (SettingsValues, SettingsValues) -> Void)?

    public var selectedTab = SettingsTab.general

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(SettingsValues.self, from: data) {
            values = stored
        } else {
            values = SettingsValues()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
