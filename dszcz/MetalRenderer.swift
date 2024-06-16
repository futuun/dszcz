import SwiftUI
import MetalKit
import ScreenCaptureKit

struct TextureSize {
    let width: Int
    let height: Int
}

struct ThreadDispatchConfig {
    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize
}

class MetalRenderer: NSObject, MTKViewDelegate {
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState

    var addDropsComputePipelineState: MTLComputePipelineState
    var addDropThreadsConfig: ThreadDispatchConfig
    var moveWavesComputePipelineState: MTLComputePipelineState
    var moveWavesThreadsConfig: ThreadDispatchConfig

    var dropletBuffer: MTLBuffer

    var stream: SCStream?
    var textureCache: CVMetalTextureCache?
    var imgTexture: MTLTexture?

    var rainTexture: [MTLTexture]
    var activeRainTextureIndex = 0
    var rainTextureSize: TextureSize

    var timers: [Timer] = []
    private let videoSampleBufferQueue = DispatchQueue(label: "com.futuun.VideoSampleBufferQueue")

    init(_ parent: MetalView) {
        self.metalDevice = parent.device
        self.metalCommandQueue = metalDevice.makeCommandQueue()!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.rasterSampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let library = self.metalDevice.makeDefaultLibrary() else {
            fatalError()
        }
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")

        do {
            try pipelineState = self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Cannot create render pipeline")
        }

        do {
            let addDropsFn = library.makeFunction(name: "addDrops")
            addDropsComputePipelineState = try self.metalDevice.makeComputePipelineState(function: addDropsFn!)

            let moveWavesFn = library.makeFunction(name: "moveWaves")
            moveWavesComputePipelineState = try self.metalDevice.makeComputePipelineState(function: moveWavesFn!)
        } catch {
            fatalError("Cannot create compute pipeline")
        }

        dropletBuffer = metalDevice.makeBuffer(length: MemoryLayout<UInt16>.size * 4, options: [])!

        let frame = NSScreen.screens[0].frame
        let scaleFactor = NSScreen.screens[0].backingScaleFactor
        rainTextureSize = TextureSize(width: Int(frame.width * scaleFactor), height: Int(frame.height * scaleFactor))

        let threadExecutionWidth = addDropsComputePipelineState.threadExecutionWidth

        addDropThreadsConfig = MetalRenderer.generateThreadDispatchConfig(
            threadExecutionWidth: threadExecutionWidth,
            maxTotalThreadsPerThreadgroup: addDropsComputePipelineState.maxTotalThreadsPerThreadgroup,
            textureSize: rainTextureSize)

        moveWavesThreadsConfig = MetalRenderer.generateThreadDispatchConfig(
            threadExecutionWidth: threadExecutionWidth,
            maxTotalThreadsPerThreadgroup: moveWavesComputePipelineState.maxTotalThreadsPerThreadgroup,
            textureSize: rainTextureSize)

        let textureDescriptorA: MTLTextureDescriptor = MTLTextureDescriptor()
        textureDescriptorA.pixelFormat = .r16Float
        textureDescriptorA.storageMode = .private
        textureDescriptorA.usage = [.shaderRead, .shaderWrite]
        textureDescriptorA.width = rainTextureSize.width
        textureDescriptorA.height = rainTextureSize.height
        textureDescriptorA.mipmapLevelCount = 1
        rainTexture = [
            self.metalDevice.makeTexture(descriptor: textureDescriptorA)!,
            self.metalDevice.makeTexture(descriptor: textureDescriptorA)!
        ]
        imgTexture = self.metalDevice.makeTexture(descriptor: textureDescriptorA)!

        super.init()

        Task {
            try await initScreenStream()
        }

        timers.append(
            Timer.scheduledTimer(timeInterval: 1/20, target: self, selector: #selector(self.addDrop), userInfo: nil, repeats: true)
        )
        timers.append(
            Timer.scheduledTimer(timeInterval: 1/120, target: self, selector: #selector(self.moveRipples), userInfo: nil, repeats: true)
        )

        timers.forEach { timer in
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    func stopTimers() {
        timers.forEach { timer in
            timer.invalidate()
        }
        timers.removeAll()
    }

    @objc func addDrop() {
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }

        computeEncoder.setComputePipelineState(addDropsComputePipelineState)
        computeEncoder.setTexture(rainTexture[activeRainTextureIndex], index: 0)

        let randomX = UInt16.random(in: 0...UInt16(rainTextureSize.width))
        let randomY = UInt16.random(in: 0...UInt16(rainTextureSize.height))
        let randomRadius = UInt16.random(in: 1...30)
        let randomStrength = UInt16.random(in: 8...12)
        memcpy(dropletBuffer.contents(), [randomX, randomY, randomRadius, randomStrength], MemoryLayout<UInt16>.size * 4)

        computeEncoder.setBuffer(dropletBuffer, offset: 0, index: 0)

        computeEncoder.dispatchThreadgroups(
            addDropThreadsConfig.threadgroupsPerGrid,
            threadsPerThreadgroup: addDropThreadsConfig.threadsPerThreadgroup)

        computeEncoder.endEncoding()
        commandBuffer.commit()
    }

    @objc func moveRipples() {
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }

        computeEncoder.setComputePipelineState(moveWavesComputePipelineState)

        computeEncoder.setTexture(rainTexture[activeRainTextureIndex], index: 0)
        computeEncoder.setTexture(rainTexture[1 - activeRainTextureIndex], index: 1)

        computeEncoder.dispatchThreadgroups(
            moveWavesThreadsConfig.threadgroupsPerGrid,
            threadsPerThreadgroup: moveWavesThreadsConfig.threadsPerThreadgroup)

        computeEncoder.endEncoding()
        commandBuffer.commit()

        activeRainTextureIndex = 1 - activeRainTextureIndex
    }

    func initScreenStream() async throws {
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)

        let sharableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let display = sharableContent.displays[0]

        let excludedWindows = sharableContent.windows.filter { window in
            window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            && window.title == "OverlayWindow"
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: excludedWindows
        )
        let configuration = SCStreamConfiguration()
        let cr = NSScreen.screens[0].frame
        let scaleFactor = NSScreen.screens[0].backingScaleFactor

        configuration.sourceRect = CGRect(x: 0, y: 0, width: cr.width, height: cr.height)
        configuration.width = Int(cr.width * scaleFactor)
        configuration.height = Int(cr.height * scaleFactor)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(NSScreen.screens[0].maximumFramesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream!.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
        
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
    }

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let re = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
        else {
            return
        }
        
        re.setRenderPipelineState(pipelineState)
        re.setFragmentTexture(imgTexture, index: 0)
        re.setFragmentTexture(rainTexture[activeRainTextureIndex], index: 1)
        re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        
        re.endEncoding()
        
        let drawable = view.currentDrawable!
        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()
        drawable.present()
    }

    static func generateThreadDispatchConfig(
        threadExecutionWidth: Int,
        maxTotalThreadsPerThreadgroup: Int,
        textureSize: TextureSize
    ) -> ThreadDispatchConfig {
        let threadsPerGroup = maxTotalThreadsPerThreadgroup / threadExecutionWidth

        return ThreadDispatchConfig(
            threadgroupsPerGrid: MTLSizeMake(
                (threadExecutionWidth + textureSize.width - 1) / threadExecutionWidth,
                (threadsPerGroup + textureSize.height - 1) / threadsPerGroup,
                1),
            threadsPerThreadgroup: MTLSizeMake(threadExecutionWidth, threadsPerGroup, 1)
        )
    }
}

extension MetalRenderer: SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if !sampleBuffer.isValid {
            return
        }

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

        guard result == kCVReturnSuccess,
              let unwrappedImageTexture = imageTexture,
              let texture = CVMetalTextureGetTexture(unwrappedImageTexture)
        else {
            return
        }

        imgTexture = texture
    }
}
