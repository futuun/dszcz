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
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState

    var addDropsComputePipelineState: MTLComputePipelineState
    var addDropThreadsConfig: ThreadDispatchConfig
    var moveWavesComputePipelineState: MTLComputePipelineState
    var moveWavesThreadsConfig: ThreadDispatchConfig

    var dropletBuffer: MTLBuffer

    var captureEngine: CaptureEngine
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
            let addDropFn = library.makeFunction(name: "addDrop")
            addDropsComputePipelineState = try self.metalDevice.makeComputePipelineState(function: addDropFn!)

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
        
        captureEngine = CaptureEngine(metalDevice: self.metalDevice)

        super.init()

        Task {
            await startCapture()
        }

        timers.append(
            Timer.scheduledTimer(timeInterval: 1/20, target: self, selector: #selector(self.addDrop), userInfo: nil, repeats: true)
        )
        timers.append(
            Timer.scheduledTimer(timeInterval: 1/120, target: self, selector: #selector(self.moveWaves), userInfo: nil, repeats: true)
        )

        timers.forEach { timer in
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    func startCapture() async {
        do {
            for try await frame in await captureEngine.startStream() {
                imgTexture = frame
            }
        } catch {
            print("\(error.localizedDescription)")
        }
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

    @objc func moveWaves() {
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard imgTexture != nil,
              let rpd = view.currentRenderPassDescriptor,
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
