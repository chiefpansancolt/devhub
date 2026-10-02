import Foundation
import Observation

public enum HistoryRetention: String, Codable, Sendable, CaseIterable {
    case thirtyDays
    case ninetyDays
    case oneYear
    case forever

    public func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .thirtyDays: calendar.date(byAdding: .day, value: -30, to: now)
        case .ninetyDays: calendar.date(byAdding: .day, value: -90, to: now)
        case .oneYear: calendar.date(byAdding: .year, value: -1, to: now)
        case .forever: nil
        }
    }
}

@MainActor
@Observable
public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []
    public private(set) var totalCount = 0
    public private(set) var fileSize: Int64 = 0
    public private(set) var lastError: String?
    public var includesOutput = true
    public var retention = HistoryRetention.oneYear

    public let fileURL: URL?
    private let log: HistoryLog?
    private var lastWrite: Task<Void, Never>?

    public init(log: HistoryLog? = nil) {
        self.log = log
        fileURL = log?.fileURL
    }

    public func startUp(now: Date = Date()) async {
        guard let log else { return }
        if let cutoff = retention.cutoff(from: now) {
            do { try await log.prune(olderThan: cutoff) } catch { lastError = error.localizedDescription }
        }
        await reload()
    }

    public func reload() async {
        guard let log else { return }
        entries = await log.recentEntries()
        totalCount = await log.entryCount()
        fileSize = await log.fileSize()
    }

    public func record(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        totalCount += 1
        guard let log else { return }

        let previous = lastWrite
        lastWrite = Task { [weak self] in
            await previous?.value
            do {
                try await log.append(entry)
                let size = await log.fileSize()
                self?.fileSize = size
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    public func waitUntilWritten() async {
        await lastWrite?.value
    }

    public func clear() async {
        await waitUntilWritten()
        entries = []
        totalCount = 0
        fileSize = 0
        guard let log else { return }
        do { try await log.clear() } catch { lastError = error.localizedDescription }
    }

    public func export(to destination: URL) async throws {
        await waitUntilWritten()
        try await log?.copy(to: destination)
    }
}
