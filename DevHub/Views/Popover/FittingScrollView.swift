import SwiftUI

/// A scroll view that is as tall as its content, up to a limit. A popover has no fixed height to give it.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight ?? maxHeight, maxHeight))
    }
}
