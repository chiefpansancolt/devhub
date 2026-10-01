import Foundation

public enum UpdateStatus: Sendable, Equatable {
    case waiting
    case updating
    case done
    case failed(String)
    /// The user cancelled before this package ran.
    case skipped
}

public struct UpdateItem: Sendable, Equatable, Identifiable {
    public let package: InstalledPackage
    public var status: UpdateStatus

    public init(package: InstalledPackage, status: UpdateStatus = .waiting) {
        self.package = package
        self.status = status
    }

    public var id: String { package.id }
}

public struct UpdateSession: Sendable, Equatable {
    public var items: [UpdateItem]
    public var isRunning: Bool

    public init(items: [UpdateItem], isRunning: Bool) {
        self.items = items
        self.isRunning = isRunning
    }

    public var doneCount: Int { items.filter { $0.status == .done }.count }
    public var skippedCount: Int { items.filter { $0.status == .skipped }.count }
    public var failedItems: [UpdateItem] { items.filter { if case .failed = $0.status { true } else { false } } }
    public var failedCount: Int { failedItems.count }

    /// Items that are no longer waiting or running.
    public var finishedCount: Int {
        items.filter { $0.status != .waiting && $0.status != .updating }.count
    }

    public var endedWithoutProblems: Bool { failedCount == 0 && skippedCount == 0 }
}

/// What one update did. The history log in a later phase writes one entry for each outcome.
public struct UpdateOutcome: Sendable, Equatable {
    public let package: InstalledPackage
    public let command: ToolCommand?
    public let result: CommandResult?
    public let status: UpdateStatus
}

public struct PackageUpdater: Sendable {
    private let scanners: [Bucket: any PackageScanner]
    private let runner: CommandRunning

    public init(scanners: [Bucket: any PackageScanner], runner: CommandRunning) {
        self.scanners = scanners
        self.runner = runner
    }

    /// Updates the packages one at a time inside each bucket. The buckets run side by side.
    /// Cancelling the calling task stops the running command and marks the packages that did not run as skipped.
    public func update(
        _ packages: [InstalledPackage],
        onStatus: @escaping @Sendable (_ packageID: String, _ status: UpdateStatus) async -> Void
    ) async -> [UpdateOutcome] {
        let byBucket = Dictionary(grouping: packages, by: \.bucket)

        let outcomes = await withTaskGroup(of: [UpdateOutcome].self) { group in
            for (bucket, bucketPackages) in byBucket {
                group.addTask {
                    var finished: [UpdateOutcome] = []
                    for package in bucketPackages {
                        finished.append(await updateOne(package, in: scanners[bucket], onStatus: onStatus))
                    }
                    return finished
                }
            }
            var all: [UpdateOutcome] = []
            for await bucketOutcomes in group { all += bucketOutcomes }
            return all
        }

        let order = Dictionary(uniqueKeysWithValues: packages.enumerated().map { ($1.id, $0) })
        return outcomes.sorted { order[$0.package.id, default: 0] < order[$1.package.id, default: 0] }
    }

    private func updateOne(
        _ package: InstalledPackage,
        in scanner: (any PackageScanner)?,
        onStatus: @Sendable (String, UpdateStatus) async -> Void
    ) async -> UpdateOutcome {
        if Task.isCancelled {
            await onStatus(package.id, .skipped)
            return UpdateOutcome(package: package, command: nil, result: nil, status: .skipped)
        }
        guard let command = scanner?.updateCommand(for: package) else {
            let status = UpdateStatus.failed("DevHub has no way to update this package.")
            await onStatus(package.id, status)
            return UpdateOutcome(package: package, command: nil, result: nil, status: status)
        }

        await onStatus(package.id, .updating)
        do {
            let result = try await runner.run(command)
            let status: UpdateStatus = result.succeeded ? .done : .failed(Self.reason(for: result))
            await onStatus(package.id, status)
            return UpdateOutcome(package: package, command: command, result: result, status: status)
        } catch is CancellationError {
            await onStatus(package.id, .skipped)
            return UpdateOutcome(package: package, command: command, result: nil, status: .skipped)
        } catch {
            let status = UpdateStatus.failed(error.localizedDescription)
            await onStatus(package.id, status)
            return UpdateOutcome(package: package, command: command, result: nil, status: status)
        }
    }

    private static func reason(for result: CommandResult) -> String {
        let firstLine = result.standardError.split(whereSeparator: \.isNewline).first
            ?? result.standardOutput.split(whereSeparator: \.isNewline).last
        return firstLine.map(String.init) ?? "The command exited with code \(result.exitCode)."
    }
}
