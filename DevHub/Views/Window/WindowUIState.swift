import DevHubCore
import Foundation
import Observation

enum WindowPage {
    case packages
    case history
}

/// What the person has selected in the window. The scan data lives in `AppState`.
@MainActor
@Observable
final class WindowUIState {
    var page = WindowPage.packages
    var scope = PackageScope(bucket: .homebrew)
    /// The buckets whose rows are open in the sidebar. A header only opens or closes its rows.
    var expandedBuckets: Set<Bucket> = [.homebrew]
    var mode = PackageListMode.updates
    var search = ""
    var inspectedID: String?
    var checkedIDs: Set<String> = []
    var isConfirmingUninstall = false
    var isConfirmingUpdateAll = false

    /// The details that were open before a menu command hid them, so the same command can show them again.
    var lastInspectedID: String?
    var lastInspectedHistoryID: UUID?
    /// Counts the requests to focus the search field. The page watches it.
    var searchFocusRequest = 0

    var historyFilter = HistoryActionFilter.all
    var historyRange = HistoryRange.lastSevenDays
    var historyBucket: Bucket?
    var historySearch = ""
    var inspectedHistoryID: UUID?
    var isConfirmingClearHistory = false

    func showHistory() {
        closeInspector()
        page = .history
    }

    func select(_ newScope: PackageScope) {
        page = .packages
        if newScope.bucket != scope.bucket {
            search = ""
            checkedIDs = []
            closeInspector()
        }
        scope = newScope
        expandedBuckets.insert(newScope.bucket)
    }

    func toggleExpanded(_ bucket: Bucket) {
        if expandedBuckets.contains(bucket) {
            expandedBuckets.remove(bucket)
        } else {
            expandedBuckets.insert(bucket)
        }
    }

    /// Clicking the open package again closes the inspector.
    func toggleInspector(for package: InstalledPackage) {
        isConfirmingUninstall = false
        inspectedID = inspectedID == package.id ? nil : package.id
    }

    func askToUninstall(_ package: InstalledPackage) {
        inspectedID = package.id
        isConfirmingUninstall = true
    }

    var hasOpenDetails: Bool {
        page == .packages ? inspectedID != nil : inspectedHistoryID != nil
    }

    var canShowDetails: Bool {
        page == .packages ? lastInspectedID != nil : lastInspectedHistoryID != nil
    }

    func hideDetails() {
        if page == .packages {
            lastInspectedID = inspectedID
            closeInspector()
        } else {
            lastInspectedHistoryID = inspectedHistoryID
            inspectedHistoryID = nil
        }
    }

    func showDetails() {
        if page == .packages {
            inspectedID = lastInspectedID
        } else {
            inspectedHistoryID = lastInspectedHistoryID
        }
    }

    /// Moves to the full list, where the search field is, and asks the page to focus it.
    func requestSearch() {
        if page == .packages { mode = .allInstalled }
        searchFocusRequest += 1
    }

    func closeInspector() {
        inspectedID = nil
        isConfirmingUninstall = false
    }

    /// Clicking the open entry again closes its details.
    func toggleHistoryEntry(_ entry: HistoryEntry) {
        inspectedHistoryID = inspectedHistoryID == entry.id ? nil : entry.id
    }
}
