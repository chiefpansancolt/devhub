import Foundation

public enum UpdateStatus: Sendable, Equatable {
    case waiting
    case updating
    case done
    case failed(String)
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
    public let action: PackageAction

    public init(items: [UpdateItem], isRunning: Bool, action: PackageAction = .update) {
        self.items = items
        self.isRunning = isRunning
        self.action = action
    }

    public var runningItem: UpdateItem? { items.first { $0.status == .updating } }

    public var doneCount: Int { items.filter { $0.status == .done }.count }
    public var skippedCount: Int { items.filter { $0.status == .skipped }.count }
    public var failedItems: [UpdateItem] { items.filter { if case .failed = $0.status { true } else { false } } }
    public var failedCount: Int { failedItems.count }

    public var finishedCount: Int {
        items.filter { $0.status != .waiting && $0.status != .updating }.count
    }

    public var endedWithoutProblems: Bool { failedCount == 0 && skippedCount == 0 }
}

public enum PackageAction: String, Sendable, Codable {
    case update
    case uninstall
    case install
}

public struct LogEntry: Sendable, Equatable {
    public enum Kind: Sendable {
        case command
        case output
        case error
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum ActionEvent: Sendable {
    case status(packageID: String, UpdateStatus)
    case log(LogEntry)
}

public struct ActionOutcome: Sendable, Equatable {
    public let package: InstalledPackage
    public let action: PackageAction
    public let command: ToolCommand?
    public let result: CommandResult?
    public let status: UpdateStatus
    public let startedAt: Date?
    public let output: [LogEntry]

    init(
        package: InstalledPackage,
        action: PackageAction,
        command: ToolCommand?,
        result: CommandResult?,
        status: UpdateStatus,
        startedAt: Date? = nil,
        output: [LogEntry] = []
    ) {
        self.package = package
        self.action = action
        self.command = command
        self.result = result
        self.status = status
        self.startedAt = startedAt
        self.output = output
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [LogEntry] = []

    func add(_ entry: LogEntry) {
        lock.withLock { lines.append(entry) }
    }

    var all: [LogEntry] { lock.withLock { lines } }
}

public struct PackageActionRunner: Sendable {
    private let scanners: [Bucket: any PackageScanner]
    private let runner: CommandRunning

    public init(scanners: [Bucket: any PackageScanner], runner: CommandRunning) {
        self.scanners = scanners
        self.runner = runner
    }

    public func update(
        _ packages: [InstalledPackage],
        onEvent: @escaping @Sendable (ActionEvent) async -> Void
    ) async -> [ActionOutcome] {
        await run(.update, packages, onEvent: onEvent)
    }

    public func install(
        _ packages: [InstalledPackage],
        onEvent: @escaping @Sendable (ActionEvent) async -> Void
    ) async -> [ActionOutcome] {
        await run(.install, packages, onEvent: onEvent)
    }

    public func uninstall(
        _ package: InstalledPackage,
        onEvent: @escaping @Sendable (ActionEvent) async -> Void
    ) async -> ActionOutcome {
        await perform(.uninstall, on: package, in: scanners[package.bucket], onEvent: onEvent)
    }

    private func run(
        _ action: PackageAction,
        _ packages: [InstalledPackage],
        onEvent: @escaping @Sendable (ActionEvent) async -> Void
    ) async -> [ActionOutcome] {
        var byBucket = Dictionary(grouping: packages, by: \.bucket)
        var outcomes: [ActionOutcome] = []

        // Other tools can depend on what Homebrew installs, such as a Node version manager or rustup, so Homebrew finishes first.
        if action == .install, let homebrew = byBucket.removeValue(forKey: .homebrew) {
            outcomes += await runInOrder(action, homebrew, onEvent: onEvent)
        }

        outcomes += await withTaskGroup(of: [ActionOutcome].self) { group in
            for bucketPackages in byBucket.values {
                group.addTask { await runInOrder(action, bucketPackages, onEvent: onEvent) }
            }
            var all: [ActionOutcome] = []
            for await bucketOutcomes in group { all += bucketOutcomes }
            return all
        }

        let order = Dictionary(uniqueKeysWithValues: packages.enumerated().map { ($1.id, $0) })
        return outcomes.sorted { order[$0.package.id, default: 0] < order[$1.package.id, default: 0] }
    }

    private func runInOrder(
        _ action: PackageAction,
        _ packages: [InstalledPackage],
        onEvent: @escaping @Sendable (ActionEvent) async -> Void
    ) async -> [ActionOutcome] {
        var finished: [ActionOutcome] = []
        for package in packages {
            finished.append(await perform(action, on: package, in: scanners[package.bucket], onEvent: onEvent))
        }
        return finished
    }

    private func perform(
        _ action: PackageAction,
        on package: InstalledPackage,
        in scanner: (any PackageScanner)?,
        onEvent: @Sendable (ActionEvent) async -> Void
    ) async -> ActionOutcome {
        if Task.isCancelled {
            await onEvent(.status(packageID: package.id, .skipped))
            return ActionOutcome(package: package, action: action, command: nil, result: nil, status: .skipped)
        }

        let command: ToolCommand? = switch action {
        case .update: scanner?.updateCommand(for: package)
        case .uninstall: scanner?.uninstallCommand(for: package)
        case .install: scanner?.installCommand(for: package)
        }
        guard let command else {
            let status = UpdateStatus.failed(Self.noCommandReason(for: action))
            await onEvent(.status(packageID: package.id, status))
            return ActionOutcome(package: package, action: action, command: nil, result: nil, status: status)
        }

        await onEvent(.status(packageID: package.id, .updating))
        await onEvent(.log(LogEntry(kind: .command, text: "$ \(command.displayText)")))
        let startedAt = Date()
        let collected = OutputCollector()
        do {
            let result = try await runner.run(command) { line in
                let entry = LogEntry(kind: line.source == .standardError ? .error : .output, text: line.text)
                collected.add(entry)
                await onEvent(.log(entry))
            }
            let status: UpdateStatus = result.succeeded ? .done : .failed(Self.reason(for: result))
            await onEvent(.status(packageID: package.id, status))
            return ActionOutcome(package: package, action: action, command: command, result: result, status: status, startedAt: startedAt, output: collected.all)
        } catch is CancellationError {
            await onEvent(.status(packageID: package.id, .skipped))
            return ActionOutcome(package: package, action: action, command: command, result: nil, status: .skipped, startedAt: startedAt, output: collected.all)
        } catch {
            let status = UpdateStatus.failed(error.localizedDescription)
            await onEvent(.status(packageID: package.id, status))
            return ActionOutcome(package: package, action: action, command: command, result: nil, status: status, startedAt: startedAt, output: collected.all)
        }
    }

    private static func noCommandReason(for action: PackageAction) -> String {
        switch action {
        case .update: String(localized: "DevHub has no way to update this package.", bundle: .module)
        case .uninstall: String(localized: "DevHub has no way to uninstall this package.", bundle: .module)
        case .install: String(localized: "DevHub has no way to install this package.", bundle: .module)
        }
    }

    private static func reason(for result: CommandResult) -> String {
        let firstLine = result.standardError.split(whereSeparator: \.isNewline).first
            ?? result.standardOutput.split(whereSeparator: \.isNewline).last
        return firstLine.map(String.init) ?? String(localized: "The command exited with code \(result.exitCode).", bundle: .module)
    }
}

extension CommandRunning {
    func run(_ command: ToolCommand, onLine: @Sendable (OutputLine) async -> Void) async throws -> CommandResult {
        var standardOutput: [String] = []
        var standardError: [String] = []
        var exitCode: Int32 = 0
        var duration = Duration.zero

        for try await event in stream(command) {
            switch event {
            case let .output(line):
                switch line.source {
                case .standardOutput: standardOutput.append(line.text)
                case .standardError: standardError.append(line.text)
                }
                await onLine(line)
            case let .finished(code, elapsed):
                exitCode = code
                duration = elapsed
            }
        }
        try Task.checkCancellation()

        return CommandResult(
            exitCode: exitCode,
            standardOutput: standardOutput.joined(separator: "\n"),
            standardError: standardError.joined(separator: "\n"),
            duration: duration
        )
    }
}
