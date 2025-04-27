import ScreenCaptureKit

class CaptureEngine: NSObject, @unchecked Sendable {
    private var videoSampleBufferQueue = DispatchQueue(label: "com.futuun.VideoSampleBufferQueue")
    private var streamOutput: CaptureEngineStreamOutput
    private var stream: SCStream?
    public var isRunning: Bool = false
    
    init(metalDevice: MTLDevice) {
        streamOutput = CaptureEngineStreamOutput(metalDevice: metalDevice)
    }

    private var streamFilter: SCContentFilter {
        get async {
            do {
                let sharableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

                let frame = NSScreen.screens[0].frame
                let display = sharableContent.displays.first { currDisplay in
                    CGRectEqualToRect(currDisplay.frame, frame)
                }!

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

            streamOutput.onError = { error in
                self.isRunning = false
                continuation.finish(throwing: error)
                self.stream = nil
            }

            do {
                stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: streamOutput)
                
                try stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
                stream?.startCapture()
                isRunning = true
            } catch {
                isRunning = false
                continuation.finish(throwing: error)
            }
        }
    }

    func stopStream() {
        guard isRunning else { return }
        
        stream?.stopCapture()
        isRunning = false
        stream = nil
    }
    
    static var canRecord: Bool {
        get async {
            do {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        }
    }
}

private class CaptureEngineStreamOutput: NSObject, SCStreamDelegate, SCStreamOutput {
    private var textureCache: CVMetalTextureCache?
    public var continuation: AsyncThrowingStream<MTLTexture, Error>.Continuation?
    var onError: ((Error) -> Void)?
    
    init(metalDevice: MTLDevice) {
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        guard type == .screen else { return }

        guard let frame = handleLatestScreenSample(from: sampleBuffer) else { return }
        continuation?.yield(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }

    private func handleLatestScreenSample(from sampleBuffer: CMSampleBuffer) -> MTLTexture? {
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
}
