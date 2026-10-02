public struct CombinedScanner: PackageScanner {
    public let bucket: Bucket

    private let scanners: [any PackageScanner]

    public init(bucket: Bucket, scanners: [any PackageScanner]) {
        self.bucket = bucket
        self.scanners = scanners
    }

    public func scan(_ reason: ScanReason) async -> ScanResult {
        await withTaskGroup(of: ScanResult.self) { group in
            for scanner in scanners {
                group.addTask { await scanner.scan(reason) }
            }
            var combined = ScanResult(packages: [])
            for await result in group {
                combined = ScanResult(packages: combined.packages + result.packages, issues: combined.issues + result.issues)
            }
            return ScanResult(packages: combined.packages, issues: combined.issues.sorted { $0.id < $1.id })
        }
    }

    public func updateCommand(for package: InstalledPackage) -> ToolCommand? {
        scanners.lazy.compactMap { $0.updateCommand(for: package) }.first
    }

    public func uninstallCommand(for package: InstalledPackage) -> ToolCommand? {
        scanners.lazy.compactMap { $0.uninstallCommand(for: package) }.first
    }
}
