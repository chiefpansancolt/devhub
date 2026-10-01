import Foundation

public enum CheckInterval: String, Codable, Sendable, CaseIterable {
    case hourly
    case everyFourHours
    case daily
    case manual

    /// How long to wait between checks. `nil` means DevHub only checks when asked.
    public var duration: Duration? {
        switch self {
        case .hourly: .seconds(60 * 60)
        case .everyFourHours: .seconds(4 * 60 * 60)
        case .daily: .seconds(24 * 60 * 60)
        case .manual: nil
        }
    }
}

public enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

public enum MenuBarIconStyle: String, Codable, Sendable, CaseIterable {
    case iconOnly
    case iconAndCount
    case countOnly
}

/// Everything the person can set. Stored as one JSON value, so a new field with a default never breaks an old file.
public struct SettingsValues: Codable, Equatable, Sendable {
    // Tools
    /// The tools the person turned off, for example because they do not use Ruby. A tool that is off is not scanned and not shown.
    public var disabledBuckets: Set<Bucket> = []

    // General
    public var checkInterval = CheckInterval.everyFourHours
    public var checkOnLaunch = true
    public var checkOnWake = false
    public var confirmUninstall = true
    public var confirmUpdateAll = true
    public var showOutputLog = true

    // Notifications
    public var notifyAboutUpdates = true
    public var notificationFrequency = NotificationFrequency.dailySummary
    public var notificationSound = false

    // Appearance
    /// A language code such as `de`. `nil` follows the language of the Mac.
    public var language: String?
    public var theme = AppTheme.system
    public var menuBarIconStyle = MenuBarIconStyle.iconAndCount

    // Homebrew
    /// A `brew` file the person chose. `nil` means DevHub looks in the usual places.
    public var brewPath: String?
    public var brewRefreshIndex = true
    public var brewIncludeCasks = true
    public var brewIncludeSelfUpdatingCasks = false
    public var brewCleanupAfterUpdate = true

    // Node
    /// A folder of Node versions the person chose. `nil` means DevHub looks for nvm, fnm, Volta and asdf.
    public var nodeFolder: String?
    public var excludedNodeVersions: Set<String> = []
    public var nodeIncludeNpm = true

    // Ruby
    public var rubyFolder: String?
    public var excludedRubyVersions: Set<String> = []
    public var gemInstallDocumentation = false

    // History
    public var historyRetention = HistoryRetention.oneYear
    public var historyIncludesOutput = true

    public init() {}

    // A value that is missing or that this version does not understand falls back to its default,
    // so a settings file from an older or newer DevHub still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        disabledBuckets = value(.disabledBuckets, disabledBuckets)
        checkInterval = value(.checkInterval, checkInterval)
        checkOnLaunch = value(.checkOnLaunch, checkOnLaunch)
        checkOnWake = value(.checkOnWake, checkOnWake)
        confirmUninstall = value(.confirmUninstall, confirmUninstall)
        confirmUpdateAll = value(.confirmUpdateAll, confirmUpdateAll)
        showOutputLog = value(.showOutputLog, showOutputLog)
        notifyAboutUpdates = value(.notifyAboutUpdates, notifyAboutUpdates)
        notificationFrequency = value(.notificationFrequency, notificationFrequency)
        notificationSound = value(.notificationSound, notificationSound)
        language = value(.language, language)
        theme = value(.theme, theme)
        menuBarIconStyle = value(.menuBarIconStyle, menuBarIconStyle)
        brewPath = value(.brewPath, brewPath)
        brewRefreshIndex = value(.brewRefreshIndex, brewRefreshIndex)
        brewIncludeCasks = value(.brewIncludeCasks, brewIncludeCasks)
        brewIncludeSelfUpdatingCasks = value(.brewIncludeSelfUpdatingCasks, brewIncludeSelfUpdatingCasks)
        brewCleanupAfterUpdate = value(.brewCleanupAfterUpdate, brewCleanupAfterUpdate)
        nodeFolder = value(.nodeFolder, nodeFolder)
        excludedNodeVersions = value(.excludedNodeVersions, excludedNodeVersions)
        nodeIncludeNpm = value(.nodeIncludeNpm, nodeIncludeNpm)
        rubyFolder = value(.rubyFolder, rubyFolder)
        excludedRubyVersions = value(.excludedRubyVersions, excludedRubyVersions)
        gemInstallDocumentation = value(.gemInstallDocumentation, gemInstallDocumentation)
        historyRetention = value(.historyRetention, historyRetention)
        historyIncludesOutput = value(.historyIncludesOutput, historyIncludesOutput)
    }

    private enum CodingKeys: String, CodingKey {
        case disabledBuckets
        case checkInterval, checkOnLaunch, checkOnWake, confirmUninstall, confirmUpdateAll, showOutputLog
        case notifyAboutUpdates, notificationFrequency, notificationSound
        case language, theme, menuBarIconStyle
        case brewPath, brewRefreshIndex, brewIncludeCasks, brewIncludeSelfUpdatingCasks, brewCleanupAfterUpdate
        case nodeFolder, excludedNodeVersions, nodeIncludeNpm
        case rubyFolder, excludedRubyVersions, gemInstallDocumentation
        case historyRetention, historyIncludesOutput
    }

    /// The fields that change what a scan finds. When one changes, DevHub scans again.
    struct ScanningFields: Equatable {
        let disabledBuckets: Set<Bucket>
        let brewPath: String?
        let includeCasks: Bool
        let includeSelfUpdatingCasks: Bool
        let nodeFolder: String?
        let excludedNodeVersions: Set<String>
        let includeNpm: Bool
        let rubyFolder: String?
        let excludedRubyVersions: Set<String>
    }

    var scanningFields: ScanningFields {
        ScanningFields(
            disabledBuckets: disabledBuckets,
            brewPath: brewPath,
            includeCasks: brewIncludeCasks,
            includeSelfUpdatingCasks: brewIncludeSelfUpdatingCasks,
            nodeFolder: nodeFolder,
            excludedNodeVersions: excludedNodeVersions,
            includeNpm: nodeIncludeNpm,
            rubyFolder: rubyFolder,
            excludedRubyVersions: excludedRubyVersions
        )
    }
}
