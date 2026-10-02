import Foundation

public enum HistoryActionFilter: Sendable, CaseIterable {
    case all
    case updates
    case uninstalls
    case checks
    case failed
}

public enum HistoryRange: Sendable, CaseIterable {
    case today
    case lastSevenDays
    case lastThirtyDays
    case allTime
}

public struct HistoryDay: Sendable, Equatable {
    public let day: Date
    public let entries: [HistoryEntry]
}

public enum HistoryListing {
    public static func filter(
        _ entries: [HistoryEntry],
        action: HistoryActionFilter,
        range: HistoryRange,
        bucket: Bucket?,
        search: String,
        now: Date,
        calendar: Calendar = .current
    ) -> [HistoryEntry] {
        let start = rangeStart(range, now: now, calendar: calendar)
        let query = search.trimmingCharacters(in: .whitespaces)

        return entries.filter { entry in
            if let start, entry.timestamp < start { return false }
            if let bucket, entry.bucket != bucket { return false }
            switch action {
            case .all: break
            case .updates: if entry.action != .update { return false }
            case .uninstalls: if entry.action != .uninstall { return false }
            case .checks: if entry.action != .check { return false }
            case .failed: if entry.ok { return false }
            }
            guard !query.isEmpty else { return true }
            return [entry.package, entry.message, entry.group].contains { $0?.localizedCaseInsensitiveContains(query) == true }
        }
    }

    public static func days(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [HistoryDay] {
        var days: [HistoryDay] = []
        for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let day = calendar.startOfDay(for: entry.timestamp)
            if let last = days.last, last.day == day {
                days[days.count - 1] = HistoryDay(day: day, entries: last.entries + [entry])
            } else {
                days.append(HistoryDay(day: day, entries: [entry]))
            }
        }
        return days
    }

    private static func rangeStart(_ range: HistoryRange, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .today: return today
        case .lastSevenDays: return calendar.date(byAdding: .day, value: -6, to: today)
        case .lastThirtyDays: return calendar.date(byAdding: .day, value: -29, to: today)
        case .allTime: return nil
        }
    }
}
