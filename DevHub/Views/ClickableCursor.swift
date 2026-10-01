import AppKit
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

// A second way to show the hand, for places where the pointer style does not show. It sets the cursor
// while the mouse is over the view, and always puts it back when the mouse leaves, the view goes away
// or the control becomes disabled.
private struct HandCursorOnHover: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isShowingHand = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                if isInside, isEnabled, !isShowingHand {
                    NSCursor.pointingHand.push()
                    isShowingHand = true
                } else if !isInside {
                    restoreCursor()
                }
            }
            .onChange(of: isEnabled) { if !isEnabled { restoreCursor() } }
            .onDisappear { restoreCursor() }
    }

    private func restoreCursor() {
        guard isShowingHand else { return }
        NSCursor.pop()
        isShowingHand = false
    }
}

extension View {
    func handCursorOnHover() -> some View {
        modifier(HandCursorOnHover())
    }
}
