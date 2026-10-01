import DevHubCore
import SwiftUI

struct MenuBarLabel: View {
    let icon: MenuBarIconState
    let style: MenuBarIconStyle

    var body: some View {
        HStack(spacing: 4) {
            if showsImage {
                Image(imageName)
            }
            if let text, style != .iconOnly {
                Text(text).monospacedDigit()
            }
        }
    }

    // A count with no icon would leave an empty menu bar item when nothing is outdated, so the icon stays then.
    private var showsImage: Bool {
        style != .countOnly || text == nil
    }

    private var imageName: String {
        switch icon {
        case .upToDate: "MenuBarUpToDate"
        case .updates: "MenuBarUpdates"
        case .updating: "MenuBarUpdating"
        case .failed: "MenuBarFailed"
        }
    }

    private var text: String? {
        switch icon {
        case .upToDate: nil
        case let .updates(count): "\(count)"
        case let .updating(finished, total): "\(finished)/\(total)"
        case let .failed(count): "\(count)"
        }
    }
}
