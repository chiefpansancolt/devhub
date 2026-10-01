import DevHubCore
import SwiftUI

struct MenuBarLabel: View {
    let icon: MenuBarIconState

    var body: some View {
        HStack(spacing: 4) {
            Image(imageName)
            if let text {
                Text(text).monospacedDigit()
            }
        }
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
