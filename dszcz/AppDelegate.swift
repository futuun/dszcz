import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.styleMask = [.borderless, .fullSizeContentView, .nonactivatingPanel]
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]
            window.level = NSWindow.Level.screenSaver
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.animationBehavior = .none
        }
    }
}
