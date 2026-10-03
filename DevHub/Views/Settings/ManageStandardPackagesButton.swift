import DevHubCore
import SwiftUI

struct ManageStandardPackagesButton: View {
    let bucket: Bucket
    @Environment(WindowUIState.self) private var windowUI
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Manage…") {
            windowUI.sheet = .standardPackages(bucket)
            openWindow(id: MainWindow.id)
            AppActivation.bringToFront()
        }
        .clickable()
    }
}
