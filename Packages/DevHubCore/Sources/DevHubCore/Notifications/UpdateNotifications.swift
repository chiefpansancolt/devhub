import Foundation

public enum NotificationFrequency: String, Codable, Sendable, CaseIterable {
    case everyUpdate
    case dailySummary
    case majorVersionsOnly
}

public struct UpdateNotification: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum NotificationAuthorization: Sendable, Equatable {
    case notAsked
    case denied
    case allowed
}

public protocol NotificationSending: Sendable {
    func send(_ notification: UpdateNotification, playSound: Bool) async
    func requestAuthorization() async -> Bool
    func authorization() async -> NotificationAuthorization
}

public struct NotificationOptions: Sendable, Equatable {
    public var isOn: Bool
    public var frequency: NotificationFrequency
    public var playsSound: Bool

    public init(isOn: Bool = false, frequency: NotificationFrequency = .dailySummary, playsSound: Bool = false) {
        self.isOn = isOn
        self.frequency = frequency
        self.playsSound = playsSound
    }

    public init(_ settings: SettingsValues) {
        self.init(isOn: settings.notifyAboutUpdates, frequency: settings.notificationFrequency, playsSound: settings.notificationSound)
    }
}

public struct NotificationPlan: Equatable, Sendable {
    public let notification: UpdateNotification?
    public let keysToRemember: Set<String>
    public let sentSummaryAt: Date?
}

public enum NotificationPlanner {
    public static func key(for package: InstalledPackage) -> String? {
        package.availableUpdate.map { "\(package.id)@\($0)" }
    }

    public static func plan(
        outdated: [InstalledPackage],
        seenKeys: Set<String>,
        isFirstCheck: Bool,
        frequency: NotificationFrequency,
        lastSummary: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let current = outdated.compactMap { package in key(for: package).map { (package, $0) } }

        if isFirstCheck {
            return NotificationPlan(notification: nil, keysToRemember: Set(current.map(\.1)), sentSummaryAt: nil)
        }
        let fresh = current.filter { !seenKeys.contains($0.1) }
        guard !fresh.isEmpty else {
            return NotificationPlan(notification: nil, keysToRemember: [], sentSummaryAt: nil)
        }
        let freshKeys = Set(fresh.map(\.1))

        switch frequency {
        case .everyUpdate:
            let packages = fresh.map(\.0)
            return NotificationPlan(notification: announcement(for: packages, headline: .new), keysToRemember: freshKeys, sentSummaryAt: nil)

        case .dailySummary:
            if let lastSummary, calendar.isDate(lastSummary, inSameDayAs: now) {
                return NotificationPlan(notification: nil, keysToRemember: [], sentSummaryAt: nil)
            }
            return NotificationPlan(notification: announcement(for: outdated, headline: .total), keysToRemember: freshKeys, sentSummaryAt: now)

        case .majorVersionsOnly:
            let majors = fresh.map(\.0).filter(isMajorUpdate)
            guard !majors.isEmpty else {
                return NotificationPlan(notification: nil, keysToRemember: freshKeys, sentSummaryAt: nil)
            }
            return NotificationPlan(notification: announcement(for: majors, headline: .major), keysToRemember: freshKeys, sentSummaryAt: nil)
        }
    }

    static func isMajorUpdate(_ package: InstalledPackage) -> Bool {
        guard let available = package.availableUpdate,
              let installedMajor = PackageVersion(package.installedVersion).major,
              let availableMajor = PackageVersion(available).major else { return false }
        return availableMajor > installedMajor
    }

    private enum Headline {
        case new
        case total
        case major
    }

    private static func announcement(for packages: [InstalledPackage], headline: Headline) -> UpdateNotification {
        let count = packages.count
        let title: String
        switch headline {
        case .new: title = String(localized: "\(count) new updates", bundle: .module)
        case .total: title = String(localized: "\(count) updates available", bundle: .module)
        case .major: title = String(localized: "\(count) major updates", bundle: .module)
        }

        let names = packages.prefix(3).map(\.name).joined(separator: ", ")
        let more = count > 3 ? " " + String(localized: "and \(count - 3) more", bundle: .module) : ""
        return UpdateNotification(title: title, body: names + more)
    }
}

public final class NotificationLedger: @unchecked Sendable {
    private struct Stored: Codable {
        var seenKeys: Set<String> = []
        var lastSummary: Date?
        var isSeeded = false
    }

    private static let key = "notificationLedger.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var stored: Stored

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    public var seenKeys: Set<String> { lock.withLock { stored.seenKeys } }
    public var lastSummary: Date? { lock.withLock { stored.lastSummary } }
    public var isSeeded: Bool { lock.withLock { stored.isSeeded } }

    public func record(_ plan: NotificationPlan, stillOutdated: Set<String>) {
        lock.withLock {
            stored.isSeeded = true
            stored.seenKeys = stored.seenKeys.union(plan.keysToRemember).intersection(stillOutdated)
            if let sent = plan.sentSummaryAt { stored.lastSummary = sent }
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.key) }
        }
    }
}
