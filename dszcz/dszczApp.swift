import SwiftUI

@main
struct rainApp: App {
    @State var window: NSWindow?

    @State public var overlayOpen: Bool = false
    @ObservedObject var permissions = AppPermissionsCheck()
    
    var body: some Scene {
        MenuBarExtra("Dszcz", systemImage: overlayOpen ? "cloud.rain": "cloud") {
            if permissions.canRecord {
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
            } else {
                Text("No screen recording permission.")
                Text("System Settings > Privacy & Security > Screen & System Audio Recording")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}

class AppPermissionsCheck: ObservableObject {
    @Published var canRecord = false

    init() {
        Task {
            await checkScreenRecordingPermissions()
        }
    }

    func checkScreenRecordingPermissions() async {
        let canRecord = await CaptureEngine.canRecord
        
        await MainActor.run {
            self.canRecord = canRecord
        }
    }
}
