import MetalKit

struct TextureSize {
    let width: Int
    let height: Int
}

struct ThreadDispatchConfig {
    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize
}

class MetalRenderer: NSObject, MTKViewDelegate {
    var overlayState: OverlayState
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState

    var addDropsComputePipelineState: MTLComputePipelineState
    var addDropThreadsConfig: ThreadDispatchConfig
    var moveWavesComputePipelineState: MTLComputePipelineState
    var moveWavesThreadsConfig: ThreadDispatchConfig
    var shouldMoveWavesTwice: Bool = NSScreen.screens[0].maximumFramesPerSecond == 60

    var dropletsBuffer: MTLBuffer

    var captureEngine: CaptureEngine
    var imgTexture: MTLTexture?

    var rainTexture: [MTLTexture]
    var activeRainTextureIndex = 0
    var rainTextureSize: TextureSize

    var timers: [Timer] = []

    private var shouldAddDrop = true
    private let dropsPerPass = Int(DROPS_PER_PASS)

    init(_ parent: MetalView) {
        self.overlayState = parent.overlayState
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

        dropletsBuffer = metalDevice.makeBuffer(length: MemoryLayout<UInt16>.size * 4 * dropsPerPass, options: [])!

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
        
        captureEngine = CaptureEngine(metalDevice: self.metalDevice)

        super.init()

        Task {
            await startCapture()
        }

        timers.append(
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
                self.shouldAddDrop = true
            })
        )
    }
    
    func startCapture() async {
        do {
            for try await frame in await captureEngine.startStream() {
                imgTexture = frame
            }
        } catch {
            print("err in start capture: \(error.localizedDescription)")
            await self.cleanup()
        }
    }

    @MainActor
    func cleanup() {
        self.stopTimers()
        overlayState.overlayOpen = false
    }

    func stopTimers() {
        timers.forEach { timer in
            timer.invalidate()
        }
        timers.removeAll()
    }
    
    func stopStream() {
        captureEngine.stopStream()
    }

    func encodeAddDrops(into commandBuffer: MTLCommandBuffer) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

        computeEncoder.setComputePipelineState(addDropsComputePipelineState)
        computeEncoder.setTexture(rainTexture[activeRainTextureIndex], index: 0)

        let dropsPointer = dropletsBuffer.contents().bindMemory(to: UInt16.self, capacity: 4 * dropsPerPass)
        for i in 0..<dropsPerPass {
            dropsPointer[i * 4 + 0] = UInt16.random(in: 0..<UInt16(rainTextureSize.width)) // x
            dropsPointer[i * 4 + 1] = UInt16.random(in: 0..<UInt16(rainTextureSize.height)) // y
            dropsPointer[i * 4 + 2] = UInt16.random(in: 1...20) // radius
            dropsPointer[i * 4 + 3] = UInt16.random(in: 8...32) // strength
        }
        computeEncoder.setBuffer(dropletsBuffer, offset: 0, index: 0)

        computeEncoder.dispatchThreadgroups(
            addDropThreadsConfig.threadgroupsPerGrid,
            threadsPerThreadgroup: addDropThreadsConfig.threadsPerThreadgroup)

        computeEncoder.endEncoding()
    }

    func encodeMoveWaves(into commandBuffer: MTLCommandBuffer) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

        computeEncoder.setComputePipelineState(moveWavesComputePipelineState)

        computeEncoder.setTexture(rainTexture[activeRainTextureIndex], index: 0)
        computeEncoder.setTexture(rainTexture[1 - activeRainTextureIndex], index: 1)

        computeEncoder.dispatchThreadgroups(
            moveWavesThreadsConfig.threadgroupsPerGrid,
            threadsPerThreadgroup: moveWavesThreadsConfig.threadsPerThreadgroup)

        computeEncoder.endEncoding()

        activeRainTextureIndex = 1 - activeRainTextureIndex
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    @MainActor
    func draw(in view: MTKView) {
        guard imgTexture != nil,
              let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = metalCommandQueue.makeCommandBuffer()
        else {
            return
        }

        encodeMoveWaves(into: commandBuffer)
        if (shouldMoveWavesTwice) {
            encodeMoveWaves(into: commandBuffer)
        }
        if shouldAddDrop {
            encodeAddDrops(into: commandBuffer)
            shouldAddDrop = false
        }
        
        guard let re = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        re.setRenderPipelineState(pipelineState)
        re.setFragmentTexture(imgTexture, index: 0)
        re.setFragmentTexture(rainTexture[activeRainTextureIndex], index: 1)
        re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        re.endEncoding()

        commandBuffer.commit()
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
