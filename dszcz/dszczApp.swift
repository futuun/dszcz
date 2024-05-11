import SwiftUI

@main
struct rainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State public var overlayOpen: Bool = true

    var screenFrame = NSScreen.main!.frame

    var body: some Scene {
        Window("Dszcz", id: "main") {
            MetalView()
                .frame(width: screenFrame.width, height: screenFrame.height)
        }
            .defaultPosition(UnitPoint(x: 0, y: 1))
        MenuBarExtra("Dszcz", systemImage: overlayOpen ? "cloud.rain": "cloud") {
            Button("Toggle overlay") {
                if overlayOpen {
                    withTransaction(\.dismissBehavior, .destructive) {
                        dismissWindow(id: "main")
                    }
                } else {
                    openWindow(id: "main")
                }

                overlayOpen.toggle()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
