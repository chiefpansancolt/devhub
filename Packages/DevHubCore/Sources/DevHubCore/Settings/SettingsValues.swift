import Foundation

public enum CheckInterval: String, Codable, Sendable, CaseIterable {
    case hourly
    case everyFourHours
    case daily
    case manual

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

public struct SettingsValues: Codable, Equatable, Sendable {
    public var disabledBuckets: Set<Bucket> = []

    public var checkInterval = CheckInterval.everyFourHours
    public var checkOnLaunch = true
    public var checkOnWake = false
    public var confirmUninstall = true
    public var confirmUpdateAll = true
    public var showOutputLog = true

    public var notifyAboutUpdates = true
    public var notificationFrequency = NotificationFrequency.dailySummary
    public var notificationSound = false

    public var language: String?
    public var theme = AppTheme.system
    public var menuBarIconStyle = MenuBarIconStyle.iconAndCount

    public var brewPath: String?
    public var brewRefreshIndex = true
    public var brewIncludeCasks = true
    public var brewIncludeSelfUpdatingCasks = false
    public var brewCleanupAfterUpdate = true

    public var nodeFolder: String?
    public var excludedNodeVersions: Set<String> = []
    public var nodeIncludeNpm = true

    public var rubyFolder: String?
    public var excludedRubyVersions: Set<String> = []
    public var gemInstallDocumentation = false

    public var rustPath: String?
    public var rustIncludeCargoTools = true
    public var pipxPath: String?
    public var uvPath: String?
    public var excludedPythonManagers: Set<String> = []
    public var pnpmPath: String?
    public var bunPath: String?
    public var yarnPath: String?
    public var excludedNodeManagers: Set<String> = []
    public var standardPackages = StandardPackageLists()
    public var disabledStandardBanners: Set<String> = []
    public var disabledRuntimeChecks: Set<String> = []
    public var notifyStandardPackages = false

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
        rustPath = value(.rustPath, rustPath)
        rustIncludeCargoTools = value(.rustIncludeCargoTools, rustIncludeCargoTools)
        pipxPath = value(.pipxPath, pipxPath)
        uvPath = value(.uvPath, uvPath)
        excludedPythonManagers = value(.excludedPythonManagers, excludedPythonManagers)
        pnpmPath = value(.pnpmPath, pnpmPath)
        bunPath = value(.bunPath, bunPath)
        yarnPath = value(.yarnPath, yarnPath)
        excludedNodeManagers = value(.excludedNodeManagers, excludedNodeManagers)
        standardPackages = value(.standardPackages, standardPackages)
        disabledStandardBanners = value(.disabledStandardBanners, disabledStandardBanners)
        disabledRuntimeChecks = value(.disabledRuntimeChecks, disabledRuntimeChecks)
        notifyStandardPackages = value(.notifyStandardPackages, notifyStandardPackages)
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
        case rustPath, rustIncludeCargoTools
        case pipxPath, uvPath, excludedPythonManagers
        case pnpmPath, bunPath, yarnPath, excludedNodeManagers
        case standardPackages, disabledStandardBanners, disabledRuntimeChecks, notifyStandardPackages
        case historyRetention, historyIncludesOutput
    }

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
        let rustPath: String?
        let includeCargoTools: Bool
        let pipxPath: String?
        let uvPath: String?
        let excludedPythonManagers: Set<String>
        let pnpmPath: String?
        let bunPath: String?
        let yarnPath: String?
        let excludedNodeManagers: Set<String>
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
            excludedRubyVersions: excludedRubyVersions,
            rustPath: rustPath,
            includeCargoTools: rustIncludeCargoTools,
            pipxPath: pipxPath,
            uvPath: uvPath,
            excludedPythonManagers: excludedPythonManagers,
            pnpmPath: pnpmPath,
            bunPath: bunPath,
            yarnPath: yarnPath,
            excludedNodeManagers: excludedNodeManagers
        )
    }
}
