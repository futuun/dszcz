import SwiftUI

@main
struct rainApp: App {
    @State var window: NSWindow?

    @State public var overlayOpen: Bool = false
    
    var body: some Scene {
        MenuBarExtra("Dszcz", systemImage: overlayOpen ? "cloud.rain": "cloud") {
            Button("Toggle overlay") {
                if overlayOpen {
                    self.window?.contentView = nil
                    self.window?.close()
                } else {
                    let window = OverlayWindow()
                    window.contentView = NSHostingView(rootView: MetalView())

                    self.window = window
                }

                overlayOpen.toggle()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
