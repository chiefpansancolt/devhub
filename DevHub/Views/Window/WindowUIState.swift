import DevHubCore
import Foundation
import Observation

enum WindowPage {
    case packages
    case history
}

enum WindowSheet: Identifiable, Equatable {
    case standardPackages(Bucket)
    case exportLists
    case importLists

    var id: String {
        switch self {
        case let .standardPackages(tool): "standard-\(tool.rawValue)"
        case .exportLists: "export"
        case .importLists: "import"
        }
    }
}

struct PendingImport: Equatable {
    let fileName: String
    let decoded: StandardListsFile.Decoded
}

@MainActor
@Observable
final class WindowUIState {
    var page = WindowPage.packages
    var scope = PackageScope(bucket: .homebrew)
    var expandedBuckets: Set<Bucket> = [.homebrew]
    var mode = PackageListMode.updates
    var search = ""
    var inspectedID: String?
    var checkedIDs: Set<String> = []
    var isConfirmingUninstall = false
    var isConfirmingUpdateAll = false
    var sheet: WindowSheet?
    var pendingImport: PendingImport?
    var standardPackagesNotice: String?

    var lastInspectedID: String?
    var lastInspectedHistoryID: UUID?
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

    func requestSearch() {
        if page == .packages { mode = .allInstalled }
        searchFocusRequest += 1
    }

    func closeInspector() {
        inspectedID = nil
        isConfirmingUninstall = false
    }

    func toggleHistoryEntry(_ entry: HistoryEntry) {
        inspectedHistoryID = inspectedHistoryID == entry.id ? nil : entry.id
    }
}
