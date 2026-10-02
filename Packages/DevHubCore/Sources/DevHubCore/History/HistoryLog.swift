import Foundation

public actor HistoryLog {
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DevHub/history.jsonl")
    }

    public nonisolated let fileURL: URL

    public init(fileURL: URL = HistoryLog.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func append(_ entry: HistoryEntry) throws {
        var line = try HistoryCoding.encoder().encode(entry)
        line.append(0x0A)

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL)
            return
        }
        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: 0) }
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

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
        lines().filter { $0.first == UInt8(ascii: "{") && $0.last == UInt8(ascii: "}") }.count
    }

    public func fileSize() -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

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
