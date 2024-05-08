import SwiftUI
import MetalKit

class MetalRenderer: NSObject, MTKViewDelegate {
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState
    
    var resolutionBuffer: MTLBuffer
    var timeBuffer: MTLBuffer
    
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
        re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        
        re.endEncoding()
        
        let drawable = view.currentDrawable!
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func updateTime(_ time: Float) {
        timeBuffer.contents().bindMemory(to: Float.self, capacity: 1)[0] = time
    }
}
