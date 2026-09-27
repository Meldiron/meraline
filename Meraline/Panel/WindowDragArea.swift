import SwiftUI

/// Empty space that moves its window when dragged, for Meraline's borderless windows. AppKit's
/// `isMovableByWindowBackground` doesn't move them once SwiftUI has taken the click, so the drag is SwiftUI's own.
/// Put it behind the content: controls, fields, and selectable text on top keep their clicks, and only the space
/// nothing else covers moves the window.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}
