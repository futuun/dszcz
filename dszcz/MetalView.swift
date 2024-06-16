import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    let device = MTLCreateSystemDefaultDevice()

    public typealias NSViewType = MTKView

    static func dismantleNSView(_ nsView: MTKView, coordinator: MetalRenderer) {
        coordinator.stopStream()
        coordinator.stopTimers()
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
    }

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(self)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.presentsWithTransaction = true
        mtkView.delegate = context.coordinator
        mtkView.device = device
        mtkView.framebufferOnly = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = NSScreen.screens[0].maximumFramesPerSecond

        return mtkView
    }
}
