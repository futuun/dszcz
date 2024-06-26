import ScreenCaptureKit

class CaptureEngine {
    private var videoSampleBufferQueue = DispatchQueue(label: "com.futuun.VideoSampleBufferQueue")
    private var streamOutput: CaptureEngineStreamOutput
    private var stream: SCStream?
    
    init(metalDevice: MTLDevice) {
        streamOutput = CaptureEngineStreamOutput(metalDevice: metalDevice)
    }
    
    private var streamFilter: SCContentFilter {
        get async {
            do {
                let sharableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let display = sharableContent.displays[0]
                
                let excludedWindows = sharableContent.windows.filter { window in
                    window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
                    && window.title == "OverlayWindow"
                }
                
                return SCContentFilter(
                    display: display,
                    excludingApplications: [],
                    exceptingWindows: excludedWindows
                )
            } catch {
                fatalError("Could not get shareable content")
            }
        }
    }
    
    private var streamConfiguration: SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let frame = NSScreen.screens[0].frame
        let scaleFactor = NSScreen.screens[0].backingScaleFactor
        
        configuration.sourceRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        configuration.width = Int(frame.width * scaleFactor)
        configuration.height = Int(frame.height * scaleFactor)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(NSScreen.screens[0].maximumFramesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        
        return configuration
    }
    
    func startStream() async -> AsyncThrowingStream<MTLTexture, Error> {
        let filter = await self.streamFilter;
        
        return AsyncThrowingStream<MTLTexture, Error> { continuation in
            streamOutput.continuation = continuation
            
            do {
                stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: streamOutput)
                
                try stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
                stream?.startCapture()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
    
    func stopStream() {
        stream?.stopCapture()
        streamOutput.continuation?.finish()
    }
}

private class CaptureEngineStreamOutput: NSObject, SCStreamDelegate, SCStreamOutput {
    private var textureCache: CVMetalTextureCache?
    public var continuation: AsyncThrowingStream<MTLTexture, Error>.Continuation?
    
    init(metalDevice: MTLDevice) {
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if !sampleBuffer.isValid {
            return
        }
        
        if type == .screen {
            guard let frame = handleLatestScreenSample(sampleBuffer: sampleBuffer) else { return }
            continuation?.yield(frame)
        }
    }
    
    func handleLatestScreenSample(sampleBuffer: CMSampleBuffer) -> MTLTexture? {
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer);
        let height = CVPixelBufferGetHeight(imageBuffer);
        
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
        
        if result == kCVReturnSuccess {
            return CVMetalTextureGetTexture(imageTexture!)!
        }
        
        return nil;
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}
