import DevHubCore
import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            switch state.popoverMode {
            case .noTools: NoToolsView()
            case .checking: CheckingView()
            case .upToDate: UpToDateView()
            case .updates: UpdatesView()
            case .updating: UpdatingView()
            case .summary: SummaryView()
            }
            Divider()
            PopoverFooter()
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
