import AppKit
import SwiftUI

final class NotchWindow: NSPanel {
    private var hostingView: NSHostingView<AnyView>!

    init(contentView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.ignoresMouseEvents = false

        // Use a large fixed window so SwiftUI content can grow/shrink freely
        // The actual visible area is controlled by the SwiftUI view's background
        let hostingView = NSHostingView(rootView: AnyView(contentView))
        self.hostingView = hostingView
        self.contentView = hostingView

        positionAtNotch()
    }

    func positionAtNotch() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Make the window wide and tall enough for expanded content
        // Centered at top of screen — SwiftUI content anchors to top-center
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 300

        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.maxY - windowHeight

        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
