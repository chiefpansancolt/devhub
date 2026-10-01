import Foundation

public enum HistoryAction: String, Codable, Sendable, CaseIterable {
    case check
    case update
    case uninstall
}

public enum HistoryTrigger: String, Codable, Sendable {
    case manual
    case updateAll
    case automatic
}

/// One line of the history file.
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let action: HistoryAction
    /// `nil` for a check of every bucket.
    public let bucket: Bucket?
    public let package: String?
    /// The Node or Ruby version that holds the package.
    public let group: String?
    public let fromVersion: String?
    public let toVersion: String?
    public let trigger: HistoryTrigger
    public let command: String
    public let exitCode: Int32
    public let durationMs: Int
    public let ok: Bool
    /// What happened in a few words: the failure reason, or for a check how many updates it found.
    public let message: String?
    /// The lines the command printed. Left out when the detail level is "actions only".
    public let output: [String]?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        action: HistoryAction,
        bucket: Bucket?,
        package: String?,
        group: String? = nil,
        fromVersion: String? = nil,
        toVersion: String? = nil,
        trigger: HistoryTrigger,
        command: String,
        exitCode: Int32,
        durationMs: Int,
        ok: Bool,
        message: String? = nil,
        output: [String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.bucket = bucket
        self.package = package
        self.group = group
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.trigger = trigger
        self.command = command
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.ok = ok
        self.message = message
        self.output = output
    }
}

enum HistoryCoding {
    // Each timestamp carries the local offset, so the file reads correctly when the Mac changes time zone.
    private static func style(fractionalSeconds: Bool) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: .colon,
            includingFractionalSeconds: fractionalSeconds,
            timeZone: .current
        )
    }

    private static func parse(_ text: String) -> Date? {
        (try? style(fractionalSeconds: true).parse(text)) ?? (try? style(fractionalSeconds: false).parse(text))
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(style(fractionalSeconds: true).format(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
            }
            return date
        }
        return decoder
    }
}

extension HistoryEntry {
    /// The entry for a finished action. `nil` when the command never started, because nothing happened.
    init?(outcome: ActionOutcome, trigger: HistoryTrigger, includesOutput: Bool) {
        guard let startedAt = outcome.startedAt else { return nil }

        let message: String?
        switch outcome.status {
        case let .failed(reason): message = reason
        case .skipped: message = String(localized: "Cancelled", bundle: .module)
        case .waiting, .updating, .done: message = nil
        }

        self.init(
            timestamp: startedAt,
            action: outcome.action == .update ? .update : .uninstall,
            bucket: outcome.package.bucket,
            package: outcome.package.name,
            group: outcome.package.group,
            fromVersion: outcome.package.installedVersion,
            toVersion: outcome.action == .update ? outcome.package.availableUpdate : nil,
            trigger: trigger,
            command: outcome.command?.displayText ?? "",
            exitCode: outcome.result?.exitCode ?? -1,
            durationMs: outcome.result.map { $0.duration.milliseconds } ?? 0,
            ok: outcome.status == .done,
            message: message,
            output: includesOutput ? outcome.output.map(\.text) : nil
        )
    }
}

extension Duration {
    var milliseconds: Int {
        let parts = components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}
