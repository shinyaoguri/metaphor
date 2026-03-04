#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import Metal
import simd

/// Provides the drawing context used within a Sketch.
///
/// Forwards drawing methods from Canvas2D and Canvas3D, and exposes convenience
/// properties for time, input, and frame state. Advanced users can access
/// `renderer`, `encoder`, `canvas`, and `canvas3D` as escape hatches.
@MainActor
public final class SketchContext {
    // MARK: - Public Properties

    /// The canvas width in pixels.
    public private(set) var width: Float

    /// The canvas height in pixels.
    public private(set) var height: Float

    /// The elapsed time in seconds since the sketch started.
    public var time: Float = 0

    /// The time elapsed in seconds since the previous frame.
    public var deltaTime: Float = 0

    /// The number of frames rendered so far.
    public var frameCount: Int = 0

    /// The input manager for mouse and keyboard state.
    public let input: InputManager

    // MARK: - Escape Hatches

    /// The underlying renderer (for advanced usage).
    public let renderer: MetaphorRenderer

    /// The current render command encoder, valid only during a frame.
    public var encoder: MTLRenderCommandEncoder? { canvas.currentEncoder }

    /// The 2D canvas (for advanced usage).
    public private(set) var canvas: Canvas2D

    /// The 3D canvas (for advanced usage).
    public private(set) var canvas3D: Canvas3D

    // MARK: - Animation Control

    /// Indicates whether the draw loop is currently running.
    public private(set) var isLooping: Bool = true

    /// Callback invoked when looping resumes (set by SketchRunner).
    var onLoop: (() -> Void)?

    /// Callback invoked when looping stops (set by SketchRunner).
    var onNoLoop: (() -> Void)?

    /// Callback invoked on a single-frame redraw (set by SketchRunner).
    var onRedraw: (() -> Void)?

    /// Callback invoked when the frame rate changes (set by SketchRunner).
    var onFrameRate: ((Int) -> Void)?

    /// Resumes the animation loop.
    public func loop() {
        isLooping = true
        onLoop?()
    }

    /// Stops the animation loop.
    public func noLoop() {
        isLooping = false
        onNoLoop?()
    }

    /// Draws a single frame (used when the loop is stopped).
    public func redraw() {
        onRedraw?()
    }

    /// Changes the target frame rate dynamically.
    /// - Parameter fps: The desired frames per second.
    public func frameRate(_ fps: Int) {
        onFrameRate?(fps)
    }

    // MARK: - Cursor Control

    /// Shows the mouse cursor.
    public func cursor() {
        NSCursor.unhide()
    }

    /// Hides the mouse cursor.
    public func noCursor() {
        NSCursor.hide()
    }

    // MARK: - Cache Management

    /// Clear all internal caches (mesh, pipeline, texture, and filter caches).
    ///
    /// Call this when switching scenes or to reclaim GPU memory.
    public func clearCaches() {
        canvas3D.clearMeshCache()
        canvas3D.clearCustomPipelineCache()
        renderer.imageFilterGPU.clearCache()
    }

    // MARK: - Canvas Resize

    /// Callback invoked when the canvas is resized (set by SketchRunner).
    var onCreateCanvas: ((Int, Int) -> Void)?

    /// Sets the canvas size (call during setup).
    /// - Parameters:
    ///   - width: The canvas width in pixels.
    ///   - height: The canvas height in pixels.
    public func createCanvas(width: Int, height: Int) {
        onCreateCanvas?(width, height)
    }

    /// Rebuilds the internal canvases after a resize (internal use).
    func rebuildCanvas(canvas: Canvas2D, canvas3D: Canvas3D) {
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.width = canvas.width
        self.height = canvas.height
    }

    // MARK: - Tween Manager

    /// The tween manager that automatically updates registered tweens each frame.
    public let tweenManager = TweenManager()

    // MARK: - GUI

    /// The parameter GUI instance for immediate-mode controls.
    public let gui = ParameterGUI()

    // MARK: - Performance HUD

    /// The performance HUD instance, or nil if disabled.
    private var performanceHUD: PerformanceHUD?

    /// Enables the performance HUD overlay.
    public func enablePerformanceHUD() {
        if performanceHUD == nil {
            performanceHUD = PerformanceHUD()
        }
    }

    /// Disables the performance HUD overlay.
    public func disablePerformanceHUD() {
        performanceHUD = nil
    }

    // MARK: - Compute State (internal)

    /// The current command buffer, valid only during the compute phase.
    var _commandBuffer: MTLCommandBuffer?

    /// The lazily created compute command encoder.
    var _computeEncoder: MTLComputeCommandEncoder?

    // MARK: - GIF Export (D-19)

    /// The GIF exporter instance.
    public let gifExporter = GIFExporter()

    // MARK: - Orbit Camera (D-20)

    /// The orbit camera instance.
    public let orbitCamera = OrbitCamera()

    // MARK: - CoreImage Filter

    /// The lazily initialized CoreImage filter wrapper.
    var _ciFilterWrapper: CIFilterWrapper?

    // MARK: - Multi-Window

    /// The shared Metal resources, set by SketchRunner for the primary window.
    var _sharedResources: SharedMetalResources?

    /// Whether this is the primary sketch context (controls global elapsed time).
    var isPrimary: Bool = false

    #if os(macOS)
    /// The secondary windows created from this context.
    private var secondaryWindows: [SketchWindow] = []

    /// Create a new secondary window.
    ///
    /// - Parameter config: The window configuration.
    /// - Returns: A new ``SketchWindow`` instance, or `nil` if creation fails.
    public func createWindow(_ config: SketchWindowConfig = SketchWindowConfig()) -> SketchWindow? {
        guard let shared = _sharedResources else {
            metaphorWarning("Cannot create window: shared resources unavailable")
            return nil
        }

        do {
            let window = try SketchWindow(config: config, sharedResources: shared)
            secondaryWindows.append(window)
            return window
        } catch {
            metaphorWarning("Failed to create window: \(error)")
            return nil
        }
    }

    /// Close all secondary windows and release their resources.
    public func closeAllWindows() {
        for window in secondaryWindows {
            window.close()
        }
        secondaryWindows.removeAll()
    }
    #endif

    // MARK: - Initialization

    init(renderer: MetaphorRenderer, canvas: Canvas2D, canvas3D: Canvas3D, input: InputManager) {
        self.renderer = renderer
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.input = input
        self.width = canvas.width
        self.height = canvas.height
    }

    // MARK: - Compute Frame Management (internal)

    /// Begins the compute phase.
    func beginCompute(commandBuffer: MTLCommandBuffer, time: Float, deltaTime: Float) {
        self._commandBuffer = commandBuffer
        self.time = time
        self.deltaTime = deltaTime
    }

    /// Ends the compute phase, finalizing the encoder if one was created.
    func endCompute() {
        _computeEncoder?.endEncoding()
        _computeEncoder = nil
        _commandBuffer = nil
    }

    // MARK: - Frame Management (internal)

    func beginFrame(encoder: MTLRenderCommandEncoder, time: Float, deltaTime: Float) {
        self.time = time
        if isPrimary {
            _sketchElapsedTime = time
        }
        self.deltaTime = deltaTime
        self.frameCount += 1
        tweenManager.update(deltaTime)
        canvas3D.begin(encoder: encoder, time: time, bufferIndex: renderer.frameBufferIndex)
        canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
    }

    func endFrame() {
        // Performance HUD overlay (before canvas.end() so it's drawn on top)
        if let hud = performanceHUD {
            hud.update(deltaTime: deltaTime)
            hud.updateGPUTime(start: renderer.lastGPUStartTime, end: renderer.lastGPUEndTime)
            hud.draw(canvas: canvas, width: Float(renderer.textureManager.width), height: Float(renderer.textureManager.height))
        }
        canvas3D.end()
        canvas.end()

        // Determine loadAction for the next frame based on whether background()
        // was called during this frame's draw(). If not called, preserve the
        // previous frame's content (Processing behavior).
        let shouldClearNext = canvas.backgroundCalledThisFrame
        renderer.textureManager.setShouldClear(shouldClearNext)
        canvas.frameWillClear = shouldClearNext

        // GIF frame capture
        captureGIFFrame()
    }
}
