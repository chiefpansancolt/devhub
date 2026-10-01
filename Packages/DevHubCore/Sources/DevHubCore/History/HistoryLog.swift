import Foundation

/// The history file: one JSON object per line, oldest first, appended as actions finish.
public actor HistoryLog {
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DevHub/history.jsonl")
    }

    public nonisolated let fileURL: URL

    public init(fileURL: URL = HistoryLog.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Adds one line. A crash can lose at most the entry that was being written.
    public func append(_ entry: HistoryEntry) throws {
        var line = try HistoryCoding.encoder().encode(entry)
        line.append(0x0A)

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// The newest entries, newest first. A line that cannot be read, such as a half-written last line, is skipped.
    public func recentEntries(limit: Int = 5000) -> [HistoryEntry] {
        let decoder = HistoryCoding.decoder()
        var entries: [HistoryEntry] = []
        for line in lines().reversed() {
            guard let entry = try? decoder.decode(HistoryEntry.self, from: line) else { continue }
            entries.append(entry)
            if entries.count == limit { break }
        }
        return entries
    }

    public func entryCount() -> Int {
        let decoder = HistoryCoding.decoder()
        return lines().filter { (try? decoder.decode(HistoryEntry.self, from: $0)) != nil }.count
    }

    public func fileSize() -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    /// Removes the entries that are older than the cutoff. Returns how many were removed.
    @discardableResult
    public func prune(olderThan cutoff: Date) throws -> Int {
        let decoder = HistoryCoding.decoder()
        var kept: [Data] = []
        var removed = 0
        for line in lines() {
            if let entry = try? decoder.decode(HistoryEntry.self, from: line), entry.timestamp < cutoff {
                removed += 1
            } else {
                kept.append(line)
            }
        }
        guard removed > 0 else { return 0 }

        var contents = Data()
        for line in kept {
            contents.append(line)
            contents.append(0x0A)
        }
        let temporary = fileURL.deletingLastPathComponent().appending(path: ".history.jsonl.tmp")
        try contents.write(to: temporary)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        return removed
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try Data().write(to: fileURL)
    }

    public func copy(to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } else {
            try Data().write(to: destination)
        }
    }

    private func lines() -> [Data] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }
}
