@preconcurrency import Metal
import MetalKit
import QuartzCore
import simd

/// Orchestrate Metal rendering and optional runtime operations for metaphor.
@MainActor
public final class MetaphorRenderer: NSObject {
    // MARK: - Public Properties

    /// The Metal device used for all GPU resource creation.
    public let device: MTLDevice

    /// The command queue used to submit work to the GPU.
    public let commandQueue: MTLCommandQueue

    /// Manage offscreen render target textures.
    public private(set) var textureManager: TextureManager

    #if os(macOS)
    /// The optional Syphon output for inter-application video sharing.
    public private(set) var syphonOutput: SyphonOutput?
    #endif

    /// The shader library used for compiling and caching Metal shader functions.
    public let shaderLibrary: ShaderLibrary

    /// The depth-stencil state cache shared across all render passes.
    public let depthStencilCache: DepthStencilCache

    /// The input manager for keyboard and mouse event handling.
    public let input: InputManager

    /// The callback invoked each frame to perform user rendering.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder for the current offscreen pass.
    ///   - time: The elapsed time in seconds since the renderer started.
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    /// The callback invoked before drawing to perform compute work.
    ///
    /// - Parameters:
    ///   - commandBuffer: The command buffer to use for creating compute encoders.
    ///   - time: The elapsed time in seconds since the renderer started.
    public var onCompute: ((MTLCommandBuffer, Double) -> Void)?

    /// The callback invoked after the main draw pass for additional rendering such as shadow passes.
    ///
    /// - Parameter commandBuffer: The command buffer for encoding additional passes.
    public var onAfterDraw: ((MTLCommandBuffer) -> Void)?

    /// The monotonic start time recorded at initialization.
    private let startTime: Double

    // MARK: - Blit Pipeline

    private var blitPipelineState: MTLRenderPipelineState?

    /// Indicate whether an external render loop drives frame rendering.
    ///
    /// When `true`, `draw(in:)` only blits the offscreen texture to screen without calling `renderFrame()`.
    public var useExternalRenderLoop: Bool = false

    // MARK: - Offline Rendering

    /// Enable offline rendering mode with deterministic frame timing.
    public var isOfflineRendering: Bool = false

    /// The frame rate used for time calculation in offline rendering mode.
    public var offlineFrameRate: Double = 60.0

    /// The current frame index in offline rendering mode.
    private var offlineFrameIndex: Int = 0

    // MARK: - Triple Buffering

    /// The semaphore that limits the number of in-flight frames to three.
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    /// The buffer index (0-2) for the current frame's triple-buffered resources.
    public private(set) var frameBufferIndex: Int = 0

    /// The next buffer index to use.
    private var nextBufferIndex: Int = 0

    // MARK: - Post Processing

    /// Indicate whether post-processing effects are available.
    public private(set) var isPostProcessAvailable: Bool = false

    /// The post-processing effect pipeline.
    public private(set) var postProcessPipeline: PostProcessPipeline?

    /// The final output texture after post-processing, used by `blitToScreen`.
    private var lastOutputTexture: MTLTexture?

    /// The GPU image filter engine, created lazily on first access.
    public private(set) lazy var imageFilterGPU: ImageFilterGPU = {
        ImageFilterGPU(device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary)
    }()

    // MARK: - Render Graph

    /// The render graph whose output becomes the final texture when set.
    public var renderGraph: RenderGraph?

    // MARK: - FBO Feedback

    /// Enable frame buffer object feedback to access the previous frame's color texture.
    public var feedbackEnabled: Bool = false

    /// The previous frame's color texture, available only when ``feedbackEnabled`` is `true`.
    public private(set) var previousFrameTexture: MTLTexture?

    // MARK: - Screenshot

    private var pendingSavePath: String?
    private var stagingTexture: MTLTexture?

    // MARK: - GPU Time

    /// The GPU start timestamp of the most recently completed frame, in seconds.
    public private(set) var lastGPUStartTime: Double = 0

    /// The GPU end timestamp of the most recently completed frame, in seconds.
    public private(set) var lastGPUEndTime: Double = 0

    // MARK: - Frame Export

    /// The frame exporter for capturing individual frames as image files.
    public let frameExporter: FrameExporter = FrameExporter()
    private var exportStagingTexture: MTLTexture?

    // MARK: - Video Export

    /// The video exporter for recording frames to a video file.
    public let videoExporter: VideoExporter = VideoExporter()
    private var videoStagingTexture: MTLTexture?

    // MARK: - Plugins

    /// The registered plugins that receive lifecycle callbacks.
    private var plugins: [MetaphorPlugin] = []

    // MARK: - Initialization

    /// Create a new renderer with the specified device and offscreen texture dimensions.
    ///
    /// - Parameters:
    ///   - device: The Metal device to use, or `nil` to use the system default.
    ///   - width: The width of the offscreen render texture in pixels.
    ///   - height: The height of the offscreen render texture in pixels.
    ///   - clearColor: The clear color for the offscreen render pass.
    /// - Throws: ``MetaphorError`` if the device or command queue cannot be created.
    public init(
        device: MTLDevice? = nil,
        width: Int = 1920,
        height: Int = 1080,
        clearColor: MTLClearColor = .black
    ) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureManager = try TextureManager(
            device: device,
            width: width,
            height: height,
            clearColor: clearColor
        )
        self.startTime = CACurrentMediaTime()
        self.shaderLibrary = try ShaderLibrary(device: device)
        self.depthStencilCache = DepthStencilCache(device: device)
        self.input = InputManager()

        super.init()

        try buildBlitPipeline()

        do {
            self.postProcessPipeline = try PostProcessPipeline(
                device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
            )
            self.isPostProcessAvailable = true
        } catch {
            metaphorWarning("PostProcessPipeline unavailable: \(error). Post-processing effects will be disabled.")
        }
    }

    #if os(macOS)
    // MARK: - Syphon

    /// Start a Syphon server with the given name for inter-application texture sharing.
    ///
    /// - Parameter name: The name to advertise for the Syphon server.
    public func startSyphonServer(name: String) {
        syphonOutput = SyphonOutput(device: device, name: name)
    }

    /// Stop the Syphon server and release its resources.
    public func stopSyphonServer() {
        syphonOutput?.stop()
        syphonOutput = nil
    }
    #endif

    // MARK: - Plugin Management

    /// Register a plugin with this renderer.
    ///
    /// The plugin's ``MetaphorPlugin/onAttach(renderer:)`` method is called immediately.
    /// - Parameter plugin: The plugin to register.
    public func addPlugin(_ plugin: MetaphorPlugin) {
        plugins.append(plugin)
        plugin.onAttach(renderer: self)
    }

    /// Remove a plugin by its identifier.
    ///
    /// The plugin's ``MetaphorPlugin/onDetach()`` method is called before removal.
    /// - Parameter id: The ``MetaphorPlugin/pluginID`` of the plugin to remove.
    public func removePlugin(id: String) {
        if let idx = plugins.firstIndex(where: { $0.pluginID == id }) {
            plugins[idx].onDetach()
            plugins.remove(at: idx)
        }
    }

    /// Return the registered plugin with the given identifier, if any.
    /// - Parameter id: The ``MetaphorPlugin/pluginID`` to search for.
    /// - Returns: The matching plugin, or `nil` if not found.
    public func plugin(id: String) -> MetaphorPlugin? {
        plugins.first(where: { $0.pluginID == id })
    }

    // MARK: - Canvas Resize

    /// Resize the offscreen canvas by recreating all render target textures.
    ///
    /// - Parameters:
    ///   - width: The new width in pixels.
    ///   - height: The new height in pixels.
    public func resizeCanvas(width: Int, height: Int) {
        // Drain all in-flight frames to ensure GPU is not using old textures.
        // The semaphore has value 3 (triple buffering); acquire all slots.
        var acquired = 0
        for _ in 0..<3 {
            let result = inflightSemaphore.wait(timeout: .now() + .seconds(5))
            if result == .timedOut {
                metaphorWarning("Timed out waiting for in-flight frame during resize")
                break
            }
            acquired += 1
        }
        defer {
            for _ in 0..<acquired {
                inflightSemaphore.signal()
            }
        }

        do {
            textureManager = try TextureManager(
                device: device,
                width: width,
                height: height
            )
        } catch {
            print("[metaphor] Failed to resize canvas: \(error)")
            return
        }
        stagingTexture = nil
        exportStagingTexture = nil
        videoStagingTexture = nil
        postProcessPipeline?.invalidateTextures()

        for plugin in plugins {
            plugin.onResize(width: width, height: height)
        }
    }

    // MARK: - Post Process API

    /// Append a post-processing effect to the pipeline.
    ///
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: PostEffect) {
        postProcessPipeline?.add(effect)
    }

    /// Remove the post-processing effect at the specified index.
    ///
    /// - Parameter index: The zero-based index of the effect to remove.
    public func removePostEffect(at index: Int) {
        postProcessPipeline?.remove(at: index)
    }

    /// Remove all post-processing effects from the pipeline.
    public func clearPostEffects() {
        postProcessPipeline?.removeAll()
    }

    /// Replace all post-processing effects with the given array.
    ///
    /// - Parameter effects: The new set of post-processing effects.
    public func setPostEffects(_ effects: [PostEffect]) {
        postProcessPipeline?.set(effects)
    }

    // MARK: - Clear Color

    /// Change the clear color of the offscreen render pass.
    ///
    /// - Parameters:
    ///   - r: The red component (0.0 to 1.0).
    ///   - g: The green component (0.0 to 1.0).
    ///   - b: The blue component (0.0 to 1.0).
    ///   - a: The alpha component (0.0 to 1.0).
    public func setClearColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
        textureManager.setClearColor(MTLClearColor(red: r, green: g, blue: b, alpha: a))
    }

    // MARK: - Rendering

    /// Return the current elapsed time in seconds.
    ///
    /// In offline rendering mode, the time is derived from the frame index and frame rate
    /// instead of wall-clock time.
    public var elapsedTime: Double {
        if isOfflineRendering {
            return Double(offlineFrameIndex) / offlineFrameRate
        }
        return CACurrentMediaTime() - startTime
    }

    /// Return the fixed delta time per frame in offline rendering mode.
    public var offlineDeltaTime: Double {
        1.0 / offlineFrameRate
    }

    /// Configure an MTKView for use with this renderer.
    ///
    /// - Parameter view: The MTKView to set up with the renderer's device and pixel formats.
    public func configure(view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self

        if let mtkView = view as? MetaphorMTKView {
            mtkView.rendererRef = self
        }
    }

    // MARK: - Screenshot

    /// Schedule a screenshot to be saved at the end of the next frame.
    ///
    /// - Parameter path: The file path where the PNG image will be written.
    public func saveScreenshot(to path: String) {
        pendingSavePath = path
    }

    // MARK: - Coordinate Conversion

    /// Convert a point from view coordinates to offscreen texture coordinates.
    ///
    /// - Parameters:
    ///   - viewPoint: The point in view coordinates (origin at bottom-left on macOS).
    ///   - viewSize: The size of the view in points.
    ///   - drawableSize: The size of the drawable in pixels.
    /// - Returns: A tuple of `(x, y)` coordinates in the offscreen texture's pixel space.
    public func viewToTextureCoordinates(
        viewPoint: CGPoint,
        viewSize: CGSize,
        drawableSize: CGSize
    ) -> (Float, Float) {
        let viewWidth = Float(viewSize.width)
        let viewHeight = Float(viewSize.height)

        // NSView coordinates (bottom-left origin) -> drawable coordinates (top-left origin)
        let scaleX = Float(drawableSize.width) / viewWidth
        let scaleY = Float(drawableSize.height) / viewHeight
        let drawX = Float(viewPoint.x) * scaleX
        let drawY = (viewHeight - Float(viewPoint.y)) * scaleY

        // Viewport -> texture coordinates
        let viewport = calculateViewport(
            drawableSize: drawableSize,
            targetAspect: textureManager.aspectRatio
        )

        let texX = (drawX - Float(viewport.originX)) / Float(viewport.width) * Float(textureManager.width)
        let texY = (drawY - Float(viewport.originY)) / Float(viewport.height) * Float(textureManager.height)

        return (texX, texY)
    }

    // MARK: - Private

    /// Copy the current frame's color texture for FBO feedback.
    private func capturePreviousFrame(commandBuffer: MTLCommandBuffer) {
        let src = textureManager.colorTexture
        let w = textureManager.width
        let h = textureManager.height

        // Recreate the texture if it does not exist or the size has changed
        if let existing = previousFrameTexture, existing.width == w, existing.height == h {
            // Reuse existing texture
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .renderTarget]
            desc.storageMode = .private
            previousFrameTexture = device.makeTexture(descriptor: desc)
            previousFrameTexture?.label = "metaphor.previousFrame"
        }

        guard let dst = previousFrameTexture,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(
            from: src,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: dst,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
    }

    private func buildBlitPipeline() throws {
        guard let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw MetaphorError.shaderCompilationFailed(
                name: "blitVertex",
                underlying: NSError(domain: "metaphor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Blit vertex shader function not found"])
            )
        }
        guard let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitFragment,
            from: ShaderLibrary.BuiltinKey.blit
        ) else {
            throw MetaphorError.shaderCompilationFailed(
                name: "blitFragment",
                underlying: NSError(domain: "metaphor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Blit fragment shader function not found"])
            )
        }

        blitPipelineState = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .sampleCount(1)
            .build()
    }

    /// Calculate an aspect-ratio-preserving viewport within the given drawable size.
    private func calculateViewport(drawableSize: CGSize, targetAspect: Float) -> MTLViewport {
        let drawableWidth = Float(drawableSize.width)
        let drawableHeight = Float(drawableSize.height)
        let drawableAspect = drawableWidth / drawableHeight

        let viewportWidth: Float
        let viewportHeight: Float
        let viewportX: Float
        let viewportY: Float

        if drawableAspect > targetAspect {
            // Pillarbox (black bars on left and right)
            viewportHeight = drawableHeight
            viewportWidth = drawableHeight * targetAspect
            viewportX = (drawableWidth - viewportWidth) / 2
            viewportY = 0
        } else {
            // Letterbox (black bars on top and bottom)
            viewportWidth = drawableWidth
            viewportHeight = drawableWidth / targetAspect
            viewportX = 0
            viewportY = (drawableHeight - viewportHeight) / 2
        }

        return MTLViewport(
            originX: Double(viewportX),
            originY: Double(viewportY),
            width: Double(viewportWidth),
            height: Double(viewportHeight),
            znear: 0,
            zfar: 1
        )
    }

    /// Return or create a managed staging texture for GPU-to-CPU readback.
    private func createOrReuseStagingTexture(cache: inout MTLTexture?) -> MTLTexture? {
        if let existing = cache,
           existing.width == textureManager.width,
           existing.height == textureManager.height {
            return existing
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: textureManager.width,
            height: textureManager.height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .managed
        guard let tex = device.makeTexture(descriptor: desc) else {
            return nil
        }
        cache = tex
        return tex
    }

    /// Return or create the staging texture used for screenshot capture.
    private func getOrCreateStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &stagingTexture)
    }

    /// Return or create the staging texture used for frame export.
    private func getOrCreateExportStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &exportStagingTexture)
    }

    /// Return or create the staging texture used for video export.
    private func getOrCreateVideoStagingTexture() -> MTLTexture? {
        createOrReuseStagingTexture(cache: &videoStagingTexture)
    }

    /// Write a texture's contents to a PNG file at the specified path.
    ///
    /// This method is `nonisolated static` so it can be called safely from a completion handler.
    ///
    /// - Parameters:
    ///   - texture: The managed staging texture containing the pixel data.
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - path: The file path where the PNG will be saved.
    nonisolated static func writePNG(
        texture: MTLTexture, width: Int, height: Int, path: String
    ) {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // BGRA -> RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = ctx.makeImage() else {
            print("[metaphor] Failed to create CGImage for screenshot")
            return
        }

        // Create the directory if it does not exist
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            print("[metaphor] Failed to create image destination: \(path)")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Blit the offscreen texture to the screen drawable with the given viewport.
    private func blitToScreen(encoder: MTLRenderCommandEncoder, viewport: MTLViewport) {
        guard let pipeline = blitPipelineState else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(viewport)
        let tex = lastOutputTexture ?? textureManager.colorTexture
        encoder.setFragmentTexture(tex, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - Render Loop

    /// Perform a complete offscreen rendering frame without presenting to screen.
    ///
    /// Execute the full pipeline in order: Compute, Offscreen Draw, Screenshot,
    /// Post-Processing, Frame/Video Export, and Syphon output.
    public func renderFrame() {
        let semaphoreResult = inflightSemaphore.wait(timeout: .now() + .seconds(3))
        if semaphoreResult == .timedOut {
            metaphorWarning("GPU frame timed out after 3s. Skipping frame.")
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        // Set the current buffer index and advance to the next
        frameBufferIndex = nextBufferIndex
        nextBufferIndex = (nextBufferIndex + 1) % 3

        commandBuffer.addCompletedHandler { [weak self] cb in
            self?.inflightSemaphore.signal()
            let gpuStart = cb.gpuStartTime
            let gpuEnd = cb.gpuEndTime
            DispatchQueue.main.async {
                self?.lastGPUStartTime = gpuStart
                self?.lastGPUEndTime = gpuEnd
            }
        }

        input.updateFrame()
        let time = elapsedTime

        // Plugin: before render
        for plugin in plugins {
            plugin.onBeforeRender(commandBuffer: commandBuffer, time: time)
        }

        // FBO feedback: copy the previous frame's color texture
        if feedbackEnabled {
            capturePreviousFrame(commandBuffer: commandBuffer)
        }

        // Compute phase
        onCompute?(commandBuffer, time)

        // Draw to offscreen texture
        if let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) {
            onDraw?(encoder, time)
            encoder.endEncoding()
        }

        // Shadow pass (update shadow map after main draw; used in the next frame)
        onAfterDraw?(commandBuffer)

        // Execute render graph (use graph output as the base texture when configured)
        let baseTexture: MTLTexture
        if let graph = renderGraph,
           let graphOutput = graph.execute(
               commandBuffer: commandBuffer, time: time, renderer: self
           ) {
            baseTexture = graphOutput
        } else {
            baseTexture = textureManager.colorTexture
        }

        // Apply post-processing effects
        let outputTexture: MTLTexture
        if let pipeline = postProcessPipeline, !pipeline.effects.isEmpty {
            outputTexture = pipeline.apply(
                source: baseTexture,
                commandBuffer: commandBuffer
            )
        } else {
            outputTexture = baseTexture
        }
        lastOutputTexture = outputTexture

        // Save screenshot (skip on failure; frame processing continues)
        if let savePath = pendingSavePath {
            pendingSavePath = nil
            if let staging = getOrCreateStagingTexture() {
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(
                        from: outputTexture,
                        sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(
                            width: textureManager.width,
                            height: textureManager.height,
                            depth: 1
                        ),
                        to: staging,
                        destinationSlice: 0, destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                    )
                    blitEncoder.synchronize(resource: staging)
                    blitEncoder.endEncoding()
                }

                let width = textureManager.width
                let height = textureManager.height
                let path = savePath
                commandBuffer.addCompletedHandler { _ in
                    MetaphorRenderer.writePNG(
                        texture: staging, width: width, height: height, path: path
                    )
                }
            }
        }

        // Frame export (capture every frame while recording)
        if frameExporter.isRecording, let exportStaging = getOrCreateExportStagingTexture() {
            frameExporter.captureFrame(
                sourceTexture: outputTexture,
                stagingTexture: exportStaging,
                commandBuffer: commandBuffer,
                width: textureManager.width,
                height: textureManager.height
            )
        }

        // Video export (capture every frame while recording)
        if videoExporter.isRecording, let videoStaging = getOrCreateVideoStagingTexture() {
            videoExporter.captureFrame(
                sourceTexture: outputTexture,
                stagingTexture: videoStaging,
                commandBuffer: commandBuffer,
                width: textureManager.width,
                height: textureManager.height
            )
        }

        // Plugin: after render (provides final texture for output plugins)
        for plugin in plugins {
            plugin.onAfterRender(texture: outputTexture, commandBuffer: commandBuffer)
        }

        // Publish to Syphon (legacy; will be replaced by SyphonPlugin)
        #if os(macOS)
        syphonOutput?.publish(
            texture: outputTexture,
            commandBuffer: commandBuffer,
            flipped: true
        )
        #endif

        commandBuffer.commit()

        if isOfflineRendering {
            offlineFrameIndex += 1
        }
    }

    /// Render a single frame in offline mode with deterministic timing.
    ///
    /// Automatically set ``isOfflineRendering`` to `true` and call ``renderFrame()``
    /// to advance the frame index.
    public func renderOfflineFrame() {
        isOfflineRendering = true
        renderFrame()
    }

    /// Reset offline rendering by setting the frame index back to zero.
    public func resetOfflineRendering() {
        offlineFrameIndex = 0
    }
}

// MARK: - MTKViewDelegate

extension MetaphorRenderer: MTKViewDelegate {
    public nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            // When not using an external render loop, render the frame here
            if !useExternalRenderLoop {
                renderFrame()
            }

            // Skip blit when the window is occluded to prevent currentDrawable from blocking
            #if os(macOS)
            if let window = view.window,
               !window.occlusionState.contains(.visible) {
                return
            }
            #endif

            // Blit to screen (preview display)
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let viewport = calculateViewport(
                drawableSize: view.drawableSize,
                targetAspect: textureManager.aspectRatio
            )

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                blitToScreen(encoder: encoder, viewport: viewport)
                encoder.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
