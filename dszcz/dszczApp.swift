import SwiftUI

@main
struct rainApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State public var overlayOpen: Bool = true
    
    var contentRect: CGRect = CGRect(x: 0, y: 0, width: NSScreen.main?.visibleFrame.width ?? 600, height: NSScreen.main?.visibleFrame.height ?? 600)

    var body: some Scene {
        Window("Dszcz", id: "main") {
            MetalView()
        }
            .defaultPosition(UnitPoint(x: 0, y: 0))
            .defaultSize(width: contentRect.width, height: contentRect.height)

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
