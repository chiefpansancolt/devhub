import SwiftUI

struct PopoverView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DevHub")
                .font(.headline)
            Text("Nothing scanned yet.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Open window") {
                    openWindow(id: MainWindow.id)
                    AppActivation.becomeRegularApp()
                }
                Spacer()
                Button("Quit DevHub") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
