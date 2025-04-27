import SwiftUI

@main
struct rainApp: App {
    @ObservedObject var permissions = AppPermissionsCheck()
    @StateObject var overlayState = OverlayState()
    @State var window: NSWindow?

    var body: some Scene {
        MenuBarExtra(
            "Dszcz",
            systemImage: overlayState.overlayOpen ? "cloud.rain": "cloud"
        ) {
            if permissions.canRecord {
                Button("Toggle overlay") {
                    if !overlayState.overlayOpen {
                        let window = OverlayWindow()
                        window.contentView = NSHostingView(
                            rootView: MetalView()
                                .environmentObject(overlayState)
                        )
                        self.window = window
                    }

                    overlayState.overlayOpen.toggle()
                }
            } else {
                Text("No screen recording permission.")
                Text("System Settings > Privacy & Security > Screen & System Audio Recording")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }.onChange(of: overlayState.overlayOpen, { oldValue, newValue in
            if !newValue {
                self.window?.contentView = nil
                self.window?.close()
                self.window = nil
            }
        })
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
