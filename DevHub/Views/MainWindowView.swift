import DevHubCore
import SwiftUI

struct MainWindowView: View {
    @State private var selection: Bucket = .homebrew

    var body: some View {
        NavigationSplitView {
            List(Bucket.allCases, id: \.self, selection: $selection) { bucket in
                Text(bucket.displayName)
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            Text(selection.displayName)
                .font(.title2)
        }
        .onAppear { AppActivation.becomeRegularApp() }
        .onDisappear { AppActivation.becomeMenuBarApp() }
    }
}
