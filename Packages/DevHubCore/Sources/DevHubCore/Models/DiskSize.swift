import Foundation

public enum DiskSize {
    public static func measure(path: String) async -> Int64? {
        await Task.detached(priority: .utility) { measureNow(path: path) }.value
    }

    // The folder walk blocks, so it stays in a plain function that never runs on the main thread.
    private static func measureNow(path: String) -> Int64? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return nil }
        let root = URL(filePath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]

        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return (try? root.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize.map(Int64.init)
        }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
