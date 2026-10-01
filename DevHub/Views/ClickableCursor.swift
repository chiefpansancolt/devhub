import SwiftUI

// Native macOS buttons keep the arrow cursor. DevHub shows the pointing hand on everything that can be clicked,
// except when the control is disabled.
private struct ClickableCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : nil)
    }
}

extension View {
    func clickable() -> some View {
        modifier(ClickableCursor())
    }
}
