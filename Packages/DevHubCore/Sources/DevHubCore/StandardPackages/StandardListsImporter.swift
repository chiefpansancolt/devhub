import Foundation

public enum ImportMode: Sendable, Equatable {
    /// Adds the names that are not in the list yet and keeps the rest.
    case merge
    /// Swaps the list for the one in the file.
    case replace
}

public struct ImportToolPlan: Equatable, Sendable, Identifiable {
    public let bucket: Bucket
    public let toAdd: [StandardEntry]
    public let alreadyThere: [StandardEntry]
    public let toRemove: [StandardEntry]
    public let resulting: [StandardEntry]

    public var id: Bucket { bucket }

    /// Whether applying this plan changes the list.
    public var changesTheList: Bool { !toAdd.isEmpty || !toRemove.isEmpty }
}

public struct ImportPlan: Equatable, Sendable {
    public let mode: ImportMode
    public let tools: [ImportToolPlan]
    public let skippedEntries: Int

    public var changedTools: [Bucket] { tools.filter(\.changesTheList).map(\.bucket) }
}

public enum StandardListsImporter {
    /// What importing `decoded` into the `current` lists would do. Tools that the file has no list for are not touched.
    public static func plan(for decoded: StandardListsFile.Decoded, into current: StandardPackageLists, mode: ImportMode) -> ImportPlan {
        let tools = StandardListsFile.tools(in: decoded.file.lists).map { bucket -> ImportToolPlan in
            let incoming = decoded.file.lists.entries(for: bucket)
            let existing = current.entries(for: bucket)
            let toAdd = incoming.filter { !existing.contains($0) }
            let alreadyThere = incoming.filter { existing.contains($0) }
            var result = StandardPackageLists()
            switch mode {
            case .merge:
                result.set(existing + toAdd, for: bucket)
                return ImportToolPlan(bucket: bucket, toAdd: toAdd, alreadyThere: alreadyThere, toRemove: [], resulting: result.entries(for: bucket))
            case .replace:
                result.set(incoming, for: bucket)
                return ImportToolPlan(bucket: bucket, toAdd: toAdd, alreadyThere: alreadyThere, toRemove: existing.filter { !incoming.contains($0) }, resulting: result.entries(for: bucket))
            }
        }
        return ImportPlan(mode: mode, tools: tools, skippedEntries: decoded.skippedEntries)
    }

    /// Writes the chosen tools of `plan` into `lists`. The other tools keep their lists.
    public static func apply(_ plan: ImportPlan, tools: Set<Bucket>, to lists: inout StandardPackageLists) {
        for tool in plan.tools where tools.contains(tool.bucket) {
            lists.set(tool.resulting, for: tool.bucket)
        }
    }
}
