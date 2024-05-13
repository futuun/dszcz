import SwiftUI
import MetalKit
import ScreenCaptureKit

class MetalRenderer: NSObject, MTKViewDelegate {
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState
    
    var resolutionBuffer: MTLBuffer
    var timeBuffer: MTLBuffer
    
    var stream: SCStream?
    var textureCache: CVMetalTextureCache?
    var imgTexture: MTLTexture?
    
    private let startDate = Date()
    
    init(_ parent: MetalView) {
        self.metalDevice = parent.device
        self.metalCommandQueue = metalDevice.makeCommandQueue()!
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.rasterSampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        if let library = self.metalDevice.makeDefaultLibrary() {
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        }
        
        do {
            try self.pipelineState = self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Cannot create render pipeline")
        }
        
        resolutionBuffer = metalDevice.makeBuffer(length: 2 * MemoryLayout<Float>.size, options: [])!
        timeBuffer = metalDevice.makeBuffer(bytes: [0], length: MemoryLayout<Float>.size, options: [])!
        
        super.init()
        
        Task {
            try await initScreenStream()
        }
    }
    
    func initScreenStream() async throws {
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
        
        let displayID: CGDirectDisplayID = CGMainDisplayID()
        let sharableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = sharableContent.displays.first(where: { $0.displayID == displayID }) else {
            fatalError("Can't find display with ID \(displayID) in sharable content")
        }

        let excludedWindows = sharableContent.windows.filter { window in
            window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: excludedWindows
        )
        let configuration = SCStreamConfiguration()
        let cr = NSScreen.main!.frame
        configuration.sourceRect = CGRect(x: 0, y: 0, width: cr.width, height: cr.height)
        configuration.width = Int(cr.width * 2)
        configuration.height = Int(cr.height * 2)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream!.addStreamOutput(self, type: .screen, sampleHandlerQueue: nil)
        
        startStream()
    }
    
    func startStream() {
        stream!.startCapture() { err in
            if err != nil {
                fatalError("Couldn't start stream capture \(String(describing: err))")
            }
        }
    }
    
    func stopStream() {
        stream!.stopCapture()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        memcpy(resolutionBuffer.contents(), [Float(size.width), Float(size.height)], MemoryLayout<Float>.size * 2)
    }
    
    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let re = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
        else {
            return
        }
        updateTime(Float(Date().timeIntervalSince(startDate)))
        
        re.setRenderPipelineState(pipelineState)
        re.setFragmentBuffer(resolutionBuffer, offset: 0, index: 0)
        re.setFragmentBuffer(timeBuffer, offset: 0, index: 1)
        re.setFragmentTexture(imgTexture, index: 0)
        re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        
        re.endEncoding()
        
        let drawable = view.currentDrawable!
        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()
        drawable.present()
    }
    
    func updateTime(_ time: Float) {
        timeBuffer.contents().bindMemory(to: Float.self, capacity: 1)[0] = time
    }
}

extension MetalRenderer: SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleLatestScreenSample(sampleBuffer: sampleBuffer)
        case .audio:
            fatalError("Audio sample could not be")
        @unknown default:
            fatalError("Only video sample can be handled")
        }
    }

    func handleLatestScreenSample(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        var imageTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(nil,
                                                               textureCache!,
                                                               imageBuffer,
                                                               nil,
                                                               .bgra8Unorm,
                                                               width,
                                                               height,
                                                               0,
                                                               &imageTexture)
        
        guard let unwrappedImageTexture = imageTexture,
              let texture = CVMetalTextureGetTexture(unwrappedImageTexture),
              result == kCVReturnSuccess else {
            return
        }
        
        imgTexture = texture
    }
}
