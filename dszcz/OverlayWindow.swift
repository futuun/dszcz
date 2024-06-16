import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeMain: Bool { return true }
    override var canBecomeKey: Bool { return true }

    public init() {
        let screenFrame = NSScreen.screens[0].frame

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]
        self.level = NSWindow.Level.screenSaver
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.title = "OverlayWindow"

        self.makeKeyAndOrderFront(nil)
    }
}
