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

/// The part of the system that shows a notification. The app uses the system notification center. Tests use a fake.
public protocol NotificationSending: Sendable {
    /// Shows the notification. Asks for permission first when the person was never asked.
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

/// What to do after a check: show a notification, and which updates to remember so they are not announced twice.
public struct NotificationPlan: Equatable, Sendable {
    public let notification: UpdateNotification?
    public let keysToRemember: Set<String>
    public let sentSummaryAt: Date?
}

public enum NotificationPlanner {
    /// One update is identified by the package and the version it would update to, so a newer version is a new update.
    public static func key(for package: InstalledPackage) -> String? {
        package.availableUpdate.map { "\(package.id)@\($0)" }
    }

    /// Decides what to announce after a check. The first check only records what is already out of date.
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
        switch (headline, count) {
        case (.new, 1): title = "1 new update"
        case (.new, _): title = "\(count) new updates"
        case (.total, 1): title = "1 update available"
        case (.total, _): title = "\(count) updates available"
        case (.major, 1): title = "1 major update"
        case (.major, _): title = "\(count) major updates"
        }

        let names = packages.prefix(3).map(\.name).joined(separator: ", ")
        let more = count > 3 ? " and \(count - 3) more" : ""
        return UpdateNotification(title: title, body: names + more)
    }
}

/// What DevHub has already announced, kept between launches so a restart does not announce it again.
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

    /// Remembers what a plan announced. Keys of updates that are no longer outdated are forgotten.
    public func record(_ plan: NotificationPlan, stillOutdated: Set<String>) {
        lock.withLock {
            stored.isSeeded = true
            stored.seenKeys = stored.seenKeys.union(plan.keysToRemember).intersection(stillOutdated)
            if let sent = plan.sentSummaryAt { stored.lastSummary = sent }
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.key) }
        }
    }
}
