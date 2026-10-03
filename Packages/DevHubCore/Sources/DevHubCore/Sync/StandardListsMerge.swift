import Foundation

public enum StandardListsMerge {
    /// Merges the lists of two Macs against the lists as they were at the last sync.
    ///
    /// An entry stays when both sides have it, or when only one side has it and it was not in the base (it was added).
    /// An entry that was in the base and is missing on one side was removed there, so it goes. Entries are matched by
    /// kind and name, so a formula and a cask with the same name are two entries.
    public static func merge(base: StandardPackageLists, local: StandardPackageLists, remote: StandardPackageLists) -> StandardPackageLists {
        var merged = StandardPackageLists()
        for bucket in Bucket.allCases {
            let inBase = Set(base.entries(for: bucket))
            let inLocal = Set(local.entries(for: bucket))
            let inRemote = Set(remote.entries(for: bucket))
            let kept = inLocal.union(inRemote).filter { entry in
                let local = inLocal.contains(entry)
                let remote = inRemote.contains(entry)
                return (local && remote) || !inBase.contains(entry)
            }
            merged.set(Array(kept), for: bucket)
        }
        return merged
    }

    /// The entries that going from `before` to `after` adds and removes, over all tools.
    public static func summary(from before: StandardPackageLists, to after: StandardPackageLists) -> SyncSummary {
        var added = 0
        var removed = 0
        for bucket in Bucket.allCases {
            let old = Set(before.entries(for: bucket))
            let new = Set(after.entries(for: bucket))
            added += new.subtracting(old).count
            removed += old.subtracting(new).count
        }
        return SyncSummary(added: added, removed: removed)
    }
}
