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
    private var _commandBuffer: MTLCommandBuffer?

    /// The lazily created compute command encoder.
    private var _computeEncoder: MTLComputeCommandEncoder?

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
        // GIF frame capture
        captureGIFFrame()
    }

    // MARK: - Shape Mode Settings

    /// Sets the coordinate interpretation mode for rectangles.
    /// - Parameter mode: The rectangle drawing mode.
    public func rectMode(_ mode: RectMode) {
        canvas.rectMode(mode)
    }

    /// Sets the coordinate interpretation mode for ellipses.
    /// - Parameter mode: The ellipse drawing mode.
    public func ellipseMode(_ mode: EllipseMode) {
        canvas.ellipseMode(mode)
    }

    /// Sets the coordinate interpretation mode for images.
    /// - Parameter mode: The image drawing mode.
    public func imageMode(_ mode: ImageMode) {
        canvas.imageMode(mode)
    }

    // MARK: - Drawing Style

    /// Returns the current shared drawing style.
    public var drawingStyle: DrawingStyle {
        get {
            DrawingStyle(
                fillColor: canvas.fillColor,
                strokeColor: canvas.strokeColor,
                hasFill: canvas.hasFill,
                hasStroke: canvas.hasStroke,
                colorModeConfig: canvas.colorModeConfig
            )
        }
        set {
            canvas.syncStyle(newValue)
            canvas3D.syncStyle(newValue)
        }
    }

    // MARK: - Color Mode

    /// Sets the color space and maximum channel values for both 2D and 3D canvases.
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value for the first channel.
    ///   - max2: The maximum value for the second channel.
    ///   - max3: The maximum value for the third channel.
    ///   - maxA: The maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        canvas.colorMode(space, max1, max2, max3, maxA)
        canvas3D.colorMode(space, max1, max2, max3, maxA)
    }

    /// Sets the color space with a uniform maximum value for both 2D and 3D canvases.
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The uniform maximum value for all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas.colorMode(space, maxAll)
        canvas3D.colorMode(space, maxAll)
    }

    // MARK: - Background

    /// Fills the background with the specified color.
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        canvas.background(color)
    }

    /// Fills the background with a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func background(_ gray: Float) {
        canvas.background(gray)
    }

    /// Fills the background with color components interpreted according to the current color mode.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.background(v1, v2, v3, a)
    }

    // MARK: - Style (2D + 3D shared)

    /// Sets the fill color for both 2D and 3D canvases.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        canvas.fill(color)
        canvas3D.fill(color)
    }

    /// Sets the fill color interpreted according to the current color mode for both 2D and 3D canvases.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.fill(v1, v2, v3, a)
        canvas3D.fill(v1, v2, v3, a)
    }

    /// Sets the fill color using a grayscale value for both 2D and 3D canvases.
    /// - Parameter gray: The grayscale intensity.
    public func fill(_ gray: Float) {
        canvas.fill(gray)
        canvas3D.fill(gray)
    }

    /// Sets the fill color using a grayscale value with alpha for both 2D and 3D canvases.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) {
        canvas.fill(gray, alpha)
        canvas3D.fill(gray, alpha)
    }

    /// Disables fill for both 2D and 3D canvases.
    public func noFill() {
        canvas.noFill()
        canvas3D.noFill()
    }

    /// Sets the stroke color for both 2D and 3D canvases.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        canvas.stroke(color)
        canvas3D.stroke(color)
    }

    /// Sets the stroke color interpreted according to the current color mode for both 2D and 3D canvases.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.stroke(v1, v2, v3, a)
        canvas3D.stroke(v1, v2, v3, a)
    }

    /// Sets the stroke color using a grayscale value for both 2D and 3D canvases.
    /// - Parameter gray: The grayscale intensity.
    public func stroke(_ gray: Float) {
        canvas.stroke(gray)
        canvas3D.stroke(gray)
    }

    /// Sets the stroke color using a grayscale value with alpha for both 2D and 3D canvases.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        canvas.stroke(gray, alpha)
        canvas3D.stroke(gray, alpha)
    }

    /// Disables stroke for both 2D and 3D canvases.
    public func noStroke() {
        canvas.noStroke()
        canvas3D.noStroke()
    }

    /// Sets the stroke weight (2D only).
    /// - Parameter weight: The line thickness in pixels.
    public func strokeWeight(_ weight: Float) {
        canvas.strokeWeight(weight)
    }

    /// Sets the stroke cap style.
    /// - Parameter cap: The end-cap style for strokes.
    public func strokeCap(_ cap: StrokeCap) {
        canvas.strokeCap(cap)
    }

    /// Sets the stroke join style.
    /// - Parameter join: The join style for stroke corners.
    public func strokeJoin(_ join: StrokeJoin) {
        canvas.strokeJoin(join)
    }

    /// Sets the blend mode for rendering.
    /// - Parameter mode: The blend mode to apply.
    public func blendMode(_ mode: BlendMode) {
        canvas.blendMode(mode)
    }

    // MARK: - Tint

    /// Sets the tint color for images.
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) {
        canvas.tint(color)
    }

    /// Sets the tint color interpreted according to the current color mode.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.tint(v1, v2, v3, a)
    }

    /// Sets the tint color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func tint(_ gray: Float) {
        canvas.tint(gray)
    }

    /// Sets the tint color using a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func tint(_ gray: Float, _ alpha: Float) {
        canvas.tint(gray, alpha)
    }

    /// Disables the image tint.
    public func noTint() {
        canvas.noTint()
    }

    // MARK: - Image

    /// Loads an image from the specified file path.
    /// - Parameter path: The file path to the image.
    /// - Returns: The loaded image.
    public func loadImage(_ path: String) throws -> MImage {
        try MImage(path: path, device: renderer.device)
    }

    /// Creates an empty image for pixel manipulation.
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    /// - Returns: A new blank image, or nil on failure.
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        MImage.createImage(width, height, device: renderer.device)
    }

    /// Applies a GPU image filter to an image.
    /// - Parameters:
    ///   - image: The target image.
    ///   - type: The filter type to apply.
    public func filter(_ image: MImage, _ type: FilterType) {
        renderer.imageFilterGPU.apply(type, to: image)
    }

    /// Creates an offscreen 2D drawing buffer.
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new Graphics instance, or nil on failure.
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        try? Graphics(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    /// Creates an offscreen 3D drawing buffer.
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new Graphics3D instance, or nil on failure.
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        try? Graphics3D(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    // MARK: - Camera Capture

    /// Creates a camera capture device and starts capturing automatically.
    /// - Parameters:
    ///   - width: The capture width in pixels (default 1280).
    ///   - height: The capture height in pixels (default 720).
    ///   - position: The camera position (default `.front`).
    /// - Returns: A started `CaptureDevice` instance.
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, position: position)
        capture.start()
        return capture
    }

    /// Draws the latest frame from a capture device at the given position.
    /// - Parameters:
    ///   - capture: The capture device.
    ///   - x: The x-coordinate of the top-left corner.
    ///   - y: The y-coordinate of the top-left corner.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y)
        }
    }

    /// Draws the latest frame from a capture device with explicit size.
    /// - Parameters:
    ///   - capture: The capture device.
    ///   - x: The x-coordinate of the top-left corner.
    ///   - y: The y-coordinate of the top-left corner.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y, w, h)
        }
    }

    /// Draws an image at the specified position.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        canvas.image(img, x, y)
    }

    /// Draws a Graphics buffer at the specified position.
    /// - Parameters:
    ///   - pg: The offscreen graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Draws a Graphics buffer with explicit size.
    /// - Parameters:
    ///   - pg: The offscreen graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Draws a Graphics3D buffer at the specified position.
    /// - Parameters:
    ///   - pg: The offscreen 3D graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Draws a Graphics3D buffer with explicit size.
    /// - Parameters:
    ///   - pg: The offscreen 3D graphics buffer.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Draws an image with explicit size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
    }

    /// Draws a sub-region of an image (for sprite sheets and tile maps).
    /// - Parameters:
    ///   - img: The source image.
    ///   - dx: The destination x-coordinate.
    ///   - dy: The destination y-coordinate.
    ///   - dw: The destination width.
    ///   - dh: The destination height.
    ///   - sx: The source x-coordinate.
    ///   - sy: The source y-coordinate.
    ///   - sw: The source width.
    ///   - sh: The source height.
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        canvas.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: - Text

    /// Sets the text rendering size.
    /// - Parameter size: The font size in points.
    public func textSize(_ size: Float) {
        canvas.textSize(size)
    }

    /// Sets the font family for text rendering.
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) {
        canvas.textFont(family)
    }

    /// Sets the text alignment.
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment (default `.baseline`).
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// Sets the line spacing for multi-line text.
    /// - Parameter leading: The line height in pixels.
    public func textLeading(_ leading: Float) {
        canvas.textLeading(leading)
    }

    /// Calculates the rendered width of a string.
    /// - Parameter string: The text to measure.
    /// - Returns: The width in pixels.
    public func textWidth(_ string: String) -> Float {
        canvas.textWidth(string)
    }

    /// Returns the font ascent for the current text settings.
    /// - Returns: The ascent value in pixels.
    public func textAscent() -> Float {
        canvas.textAscent()
    }

    /// Returns the font descent for the current text settings.
    /// - Returns: The descent value in pixels.
    public func textDescent() -> Float {
        canvas.textDescent()
    }

    /// Draws text at the specified position.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        canvas.text(string, x, y)
    }

    /// Draws text within a bounding box with automatic word wrapping.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate of the box.
    ///   - y: The y-coordinate of the box.
    ///   - w: The box width.
    ///   - h: The box height.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.text(string, x, y, w, h)
    }

    // MARK: - Screenshot

    /// Saves a screenshot to the specified file path.
    /// - Parameter path: The output file path.
    public func save(_ path: String) {
        renderer.saveScreenshot(to: path)
    }

    /// Begins sequential frame export.
    /// - Parameters:
    ///   - directory: The output directory (nil creates one on the Desktop automatically).
    ///   - pattern: The filename pattern with a frame number placeholder.
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        let dir: String
        if let directory {
            dir = directory
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            dir = NSHomeDirectory() + "/Desktop/metaphor_frames_\(formatter.string(from: Date()))"
        }
        renderer.frameExporter.beginSequence(directory: dir, pattern: pattern)
    }

    /// Stops sequential frame export.
    public func endRecord() {
        renderer.frameExporter.endSequence()
    }

    /// Begins video recording.
    /// - Parameters:
    ///   - path: The output file path (nil generates one on the Desktop automatically).
    ///   - config: The video export configuration.
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).\(config.format.fileExtension)"
        }
        try? renderer.videoExporter.beginRecord(
            path: actualPath,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height,
            config: config
        )
    }

    /// Ends video recording.
    /// - Parameter completion: A callback invoked when writing finishes.
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        renderer.videoExporter.endRecord(completion: completion)
    }

    /// Saves the current frame as a single image file (Processing-compatible).
    /// - Parameter filename: The output filename (nil auto-generates a numbered name).
    public func saveFrame(_ filename: String? = nil) {
        let name: String
        if let filename {
            name = filename
        } else {
            name = "screen-\(String(format: "%04d", frameCount)).png"
        }
        let path = NSHomeDirectory() + "/Desktop/" + name
        renderer.saveScreenshot(to: path)
    }

    /// Saves a timestamped screenshot to the Desktop.
    public func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "metaphor_\(formatter.string(from: Date())).png"
        let path = NSHomeDirectory() + "/Desktop/" + name
        save(path)
    }

    // MARK: - Offline Rendering

    /// Indicates whether offline rendering mode is active.
    public var isOfflineRendering: Bool {
        renderer.isOfflineRendering
    }

    /// Begins offline rendering mode.
    ///
    /// Elapsed time becomes deterministic, enabling high-quality video rendering
    /// without frame drops.
    /// - Parameter fps: The target frame rate (default 60).
    public func beginOfflineRender(fps: Double = 60) {
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = fps
        renderer.resetOfflineRendering()
    }

    /// Ends offline rendering mode.
    public func endOfflineRender() {
        renderer.isOfflineRendering = false
    }

    // MARK: - FBO Feedback

    /// Enables frame buffer feedback.
    ///
    /// When enabled, the previous frame's color texture is copied at the start
    /// of each frame and can be retrieved as an `MImage` via ``previousFrame()``.
    public func enableFeedback() {
        renderer.feedbackEnabled = true
    }

    /// Disables frame buffer feedback.
    public func disableFeedback() {
        renderer.feedbackEnabled = false
    }

    /// Returns the previous frame's rendering result as an image.
    ///
    /// Call ``enableFeedback()`` before using this method. Returns nil when
    /// feedback is disabled or on the very first frame.
    /// - Returns: The previous frame as an `MImage`, or nil.
    public func previousFrame() -> MImage? {
        guard let tex = renderer.previousFrameTexture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Post Process

    /// Creates a custom post-processing effect from MSL fragment shader source.
    ///
    /// The shader source should include `PostProcessShaders.commonStructs` as a prefix.
    /// - Parameters:
    ///   - name: The effect name (used as the library key).
    ///   - source: The MSL shader source code.
    ///   - fragmentFunction: The fragment shader function name.
    /// - Returns: A `CustomPostEffect` instance.
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw MetaphorError.postProcessShaderNotFound(fragmentFunction)
        }
        return CustomPostEffect(name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
    }

    /// Adds a post-processing effect to the pipeline.
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: PostEffect) {
        renderer.addPostEffect(effect)
    }

    /// Removes a post-processing effect at the specified index.
    /// - Parameter index: The index of the effect to remove.
    public func removePostEffect(at index: Int) {
        renderer.removePostEffect(at: index)
    }

    /// Removes all post-processing effects from the pipeline.
    public func clearPostEffects() {
        renderer.clearPostEffects()
    }

    /// Replaces all post-processing effects with the given array.
    /// - Parameter effects: The new array of post-processing effects.
    public func setPostEffects(_ effects: [PostEffect]) {
        renderer.setPostEffects(effects)
    }

    // MARK: - Unified Transform Stack

    /// Saves both 2D and 3D transform and style state onto the stack.
    public func push() {
        canvas.push()
        canvas3D.pushState()
    }

    /// Restores both 2D and 3D transform and style state from the stack.
    public func pop() {
        canvas.pop()
        canvas3D.popState()
    }

    /// Saves only the 2D style state onto the stack.
    public func pushStyle() {
        canvas.pushStyle()
    }

    /// Restores only the 2D style state from the stack.
    public func popStyle() {
        canvas.popStyle()
    }

    /// Applies a 2D translation.
    /// - Parameters:
    ///   - x: The horizontal translation.
    ///   - y: The vertical translation.
    public func translate(_ x: Float, _ y: Float) {
        canvas.translate(x, y)
    }

    /// Applies a 2D rotation.
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) {
        canvas.rotate(angle)
    }

    /// Applies a 2D scale.
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) {
        canvas.scale(sx, sy)
    }

    /// Applies a uniform scale to both the 2D and 3D canvases.
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) {
        canvas.scale(s)
        canvas3D.scale(s, s, s)
    }

    // MARK: - 2D Shapes

    /// Draws a rectangle.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.rect(x, y, w, h)
    }

    /// Draws a rounded rectangle with a uniform corner radius.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - r: The corner radius.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        canvas.rect(x, y, w, h, r)
    }

    /// Draws a rounded rectangle with individual corner radii.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - tl: The top-left corner radius.
    ///   - tr: The top-right corner radius.
    ///   - br: The bottom-right corner radius.
    ///   - bl: The bottom-left corner radius.
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        canvas.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// Draws a rectangle filled with a linear gradient.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - c1: The start color.
    ///   - c2: The end color.
    ///   - axis: The gradient direction (default `.vertical`).
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        canvas.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// Draws a radial gradient.
    /// - Parameters:
    ///   - cx: The center x-coordinate.
    ///   - cy: The center y-coordinate.
    ///   - radius: The gradient radius.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the edge.
    ///   - segments: The number of segments (default 36).
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        canvas.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// Draws an ellipse.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.ellipse(x, y, w, h)
    }

    /// Draws a circle.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - diameter: The circle diameter.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        canvas.circle(x, y, diameter)
    }

    /// Draws a square.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - size: The side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        canvas.square(x, y, size)
    }

    /// Draws a quadrilateral defined by four corner points.
    /// - Parameters:
    ///   - x1: The x-coordinate of the first vertex.
    ///   - y1: The y-coordinate of the first vertex.
    ///   - x2: The x-coordinate of the second vertex.
    ///   - y2: The y-coordinate of the second vertex.
    ///   - x3: The x-coordinate of the third vertex.
    ///   - y3: The y-coordinate of the third vertex.
    ///   - x4: The x-coordinate of the fourth vertex.
    ///   - y4: The y-coordinate of the fourth vertex.
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Draws a line between two points.
    /// - Parameters:
    ///   - x1: The start x-coordinate.
    ///   - y1: The start y-coordinate.
    ///   - x2: The end x-coordinate.
    ///   - y2: The end y-coordinate.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        canvas.line(x1, y1, x2, y2)
    }

    /// Draws a triangle defined by three vertices.
    /// - Parameters:
    ///   - x1: The x-coordinate of the first vertex.
    ///   - y1: The y-coordinate of the first vertex.
    ///   - x2: The x-coordinate of the second vertex.
    ///   - y2: The y-coordinate of the second vertex.
    ///   - x3: The x-coordinate of the third vertex.
    ///   - y3: The y-coordinate of the third vertex.
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        canvas.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// Draws a polygon from an array of coordinate tuples.
    /// - Parameter points: An array of (x, y) coordinate tuples.
    public func polygon(_ points: [(Float, Float)]) {
        canvas.polygon(points)
    }

    /// Draws a polygon from an array of Vec2 points.
    /// - Parameter points: An array of Vec2 points.
    public func polygon(_ points: [Vec2]) {
        canvas.polygon(points.map { ($0.x, $0.y) })
    }

    /// Draws an arc.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - w: The width of the bounding ellipse.
    ///   - h: The height of the bounding ellipse.
    ///   - startAngle: The starting angle in radians.
    ///   - stopAngle: The ending angle in radians.
    ///   - mode: The arc drawing mode (default `.open`).
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        canvas.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// Draws a cubic Bezier curve.
    /// - Parameters:
    ///   - x1: The start point x-coordinate.
    ///   - y1: The start point y-coordinate.
    ///   - cx1: The first control point x-coordinate.
    ///   - cy1: The first control point y-coordinate.
    ///   - cx2: The second control point x-coordinate.
    ///   - cy2: The second control point y-coordinate.
    ///   - x2: The end point x-coordinate.
    ///   - y2: The end point y-coordinate.
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// Draws a single point.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func point(_ x: Float, _ y: Float) {
        canvas.point(x, y)
    }

    // MARK: - Custom Shapes (beginShape / endShape)

    /// Begins recording a vertex-based custom shape.
    /// - Parameter mode: The shape drawing mode (default `.polygon`).
    public func beginShape(_ mode: ShapeMode = .polygon) {
        canvas.beginShape(mode)
    }

    /// Adds a vertex to the current shape.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func vertex(_ x: Float, _ y: Float) {
        canvas.vertex(x, y)
    }

    /// Adds a cubic Bezier vertex with control points and an endpoint.
    /// - Parameters:
    ///   - cx1: The first control point x-coordinate.
    ///   - cy1: The first control point y-coordinate.
    ///   - cx2: The second control point x-coordinate.
    ///   - cy2: The second control point y-coordinate.
    ///   - x: The endpoint x-coordinate.
    ///   - y: The endpoint y-coordinate.
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Adds a Catmull-Rom spline vertex.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func curveVertex(_ x: Float, _ y: Float) {
        canvas.curveVertex(x, y)
    }

    /// Sets the number of subdivisions for curve segments.
    /// - Parameter n: The subdivision count.
    public func curveDetail(_ n: Int) {
        canvas.curveDetail(n)
    }

    /// Sets the tightness of Catmull-Rom curves.
    /// - Parameter t: The tightness value.
    public func curveTightness(_ t: Float) {
        canvas.curveTightness(t)
    }

    /// Begins recording a contour (hole) within the current shape.
    public func beginContour() {
        canvas.beginContour()
    }

    /// Ends the current contour (hole) recording.
    public func endContour() {
        canvas.endContour()
    }

    /// Adds a vertex with a per-vertex color (2D).
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        canvas.vertex(x, y, color)
    }

    /// Adds a vertex with UV texture coordinates (2D).
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - u: The U texture coordinate.
    ///   - v: The V texture coordinate.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        canvas.vertex(x, y, u, v)
    }

    /// Ends the current shape recording and draws the shape.
    /// - Parameter close: Whether to close the shape (default `.open`).
    public func endShape(_ close: CloseMode = .open) {
        canvas.endShape(close)
    }

    // MARK: - 3D Custom Shapes (beginShape / endShape)

    /// Begins recording a 3D vertex-based custom shape.
    /// - Parameter mode: The shape drawing mode (default `.polygon`).
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        canvas3D.beginShape(mode)
    }

    /// Adds a 3D vertex to the current shape.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.vertex(x, y, z)
    }

    /// Adds a 3D vertex with a per-vertex color.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        canvas3D.vertex(x, y, z, color)
    }

    /// Sets the normal vector for the next 3D vertex.
    /// - Parameters:
    ///   - nx: The normal x-component.
    ///   - ny: The normal y-component.
    ///   - nz: The normal z-component.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        canvas3D.normal(nx, ny, nz)
    }

    /// Ends the 3D shape recording and draws the shape.
    /// - Parameter close: Whether to close the shape (default `.open`).
    public func endShape3D(_ close: CloseMode = .open) {
        canvas3D.endShape(close)
    }

    /// Draws a Catmull-Rom spline curve through four points.
    /// - Parameters:
    ///   - x1: The first guide point x-coordinate.
    ///   - y1: The first guide point y-coordinate.
    ///   - x2: The start of the visible curve x-coordinate.
    ///   - y2: The start of the visible curve y-coordinate.
    ///   - x3: The end of the visible curve x-coordinate.
    ///   - y3: The end of the visible curve y-coordinate.
    ///   - x4: The second guide point x-coordinate.
    ///   - y4: The second guide point y-coordinate.
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    // MARK: - 3D Camera

    /// Sets the camera position and orientation.
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector (default Y-up).
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        canvas3D.camera(eye: eye, center: center, up: up)
    }

    /// Sets the camera position and orientation using positional arguments (p5.js-style).
    /// - Parameters:
    ///   - eyeX: The camera x-position.
    ///   - eyeY: The camera y-position.
    ///   - eyeZ: The camera z-position.
    ///   - centerX: The look-at target x-coordinate.
    ///   - centerY: The look-at target y-coordinate.
    ///   - centerZ: The look-at target z-coordinate.
    ///   - upX: The up vector x-component.
    ///   - upY: The up vector y-component.
    ///   - upZ: The up vector z-component.
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        canvas3D.camera(
            eye: SIMD3(eyeX, eyeY, eyeZ),
            center: SIMD3(centerX, centerY, centerZ),
            up: SIMD3(upX, upY, upZ)
        )
    }

    /// Configures perspective projection.
    /// - Parameters:
    ///   - fov: The field of view in radians (default pi/3).
    ///   - near: The near clipping plane distance (default 0.1).
    ///   - far: The far clipping plane distance (default 10000).
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        canvas3D.perspective(fov: fov, near: near, far: far)
    }

    /// Switches to orthographic projection.
    /// - Parameters:
    ///   - left: The left clipping plane (nil uses canvas bounds).
    ///   - right: The right clipping plane (nil uses canvas bounds).
    ///   - bottom: The bottom clipping plane (nil uses canvas bounds).
    ///   - top: The top clipping plane (nil uses canvas bounds).
    ///   - near: The near clipping plane distance (default -1000).
    ///   - far: The far clipping plane distance (default 1000).
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: - 3D Lighting

    /// Enables default lighting.
    public func lights() {
        canvas3D.lights()
    }

    /// Removes all lights from the scene.
    public func noLights() {
        canvas3D.noLights()
    }

    /// Sets the direction of the directional light.
    /// - Parameters:
    ///   - x: The direction x-component.
    ///   - y: The direction y-component.
    ///   - z: The direction z-component.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// Sets the direction and color of the directional light.
    /// - Parameters:
    ///   - x: The direction x-component.
    ///   - y: The direction y-component.
    ///   - z: The direction z-component.
    ///   - color: The light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// Adds a point light to the scene.
    /// - Parameters:
    ///   - x: The light x-position.
    ///   - y: The light y-position.
    ///   - z: The light z-position.
    ///   - color: The light color (default white).
    ///   - falloff: The attenuation factor (default 0.1).
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// Adds a spot light to the scene.
    /// - Parameters:
    ///   - x: The light x-position.
    ///   - y: The light y-position.
    ///   - z: The light z-position.
    ///   - dirX: The spotlight direction x-component.
    ///   - dirY: The spotlight direction y-component.
    ///   - dirZ: The spotlight direction z-component.
    ///   - angle: The cone angle in radians (default pi/6).
    ///   - falloff: The attenuation factor (default 0.01).
    ///   - color: The light color (default white).
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// Sets the ambient light intensity.
    /// - Parameter strength: The ambient light strength.
    public func ambientLight(_ strength: Float) {
        canvas3D.ambientLight(strength)
    }

    /// Sets the ambient light color using RGB components.
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        canvas3D.ambientLight(r, g, b)
    }

    // MARK: - Shadow Mapping

    /// Enables shadow mapping.
    /// - Parameter resolution: The shadow map resolution in pixels (default 2048).
    public func enableShadows(resolution: Int = 2048) {
        if canvas3D.shadowMap == nil {
            canvas3D.shadowMap = try? ShadowMap(
                device: renderer.device,
                shaderLibrary: renderer.shaderLibrary,
                resolution: resolution
            )
        }
    }

    /// Disables shadow mapping.
    public func disableShadows() {
        canvas3D.shadowMap = nil
    }

    /// Sets the shadow bias to prevent shadow acne.
    /// - Parameter value: The bias value.
    public func shadowBias(_ value: Float) {
        canvas3D.shadowMap?.shadowBias = value
    }

    // MARK: - 3D Material

    /// Sets the specular highlight color.
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        canvas3D.specular(color)
    }

    /// Sets the specular highlight color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func specular(_ gray: Float) {
        canvas3D.specular(gray)
    }

    /// Sets the specular shininess exponent.
    /// - Parameter value: The shininess value.
    public func shininess(_ value: Float) {
        canvas3D.shininess(value)
    }

    /// Sets the emissive color.
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        canvas3D.emissive(color)
    }

    /// Sets the emissive color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func emissive(_ gray: Float) {
        canvas3D.emissive(gray)
    }

    /// Sets the metallic coefficient.
    /// - Parameter value: The metallic value between 0.0 and 1.0.
    public func metallic(_ value: Float) {
        canvas3D.metallic(value)
    }

    /// Sets the PBR roughness and automatically switches to PBR mode.
    /// - Parameter value: The roughness from 0.0 (mirror) to 1.0 (fully diffuse).
    public func roughness(_ value: Float) {
        canvas3D.roughness(value)
    }

    /// Sets the PBR ambient occlusion factor.
    /// - Parameter value: The occlusion from 0.0 (fully occluded) to 1.0 (no occlusion).
    public func ambientOcclusion(_ value: Float) {
        canvas3D.ambientOcclusion(value)
    }

    /// Toggles PBR mode explicitly.
    /// - Parameter enabled: Pass true for Cook-Torrance GGX, false for Blinn-Phong.
    public func pbr(_ enabled: Bool) {
        canvas3D.pbr(enabled)
    }

    // MARK: - 3D Custom Material

    /// Creates a custom material from MSL shader source.
    ///
    /// Compiles the MSL source and builds a `CustomMaterial` from the specified
    /// fragment function. The source should include `BuiltinShaders.canvas3DStructs`
    /// as a prefix.
    /// - Parameters:
    ///   - source: The MSL shader source code.
    ///   - fragmentFunction: The fragment shader function name.
    ///   - vertexFunction: An optional custom vertex shader function name.
    /// - Returns: A `CustomMaterial` instance.
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw CustomMaterialError.shaderNotFound(fragmentFunction)
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw CustomMaterialError.shaderNotFound(vtxName)
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    /// Applies a custom material to subsequent 3D draws.
    /// - Parameter customMaterial: The custom material to use.
    public func material(_ customMaterial: CustomMaterial) {
        canvas3D.material(customMaterial)
    }

    /// Removes the custom material and reverts to the built-in shader.
    public func noMaterial() {
        canvas3D.noMaterial()
    }

    // MARK: - 3D Texture

    /// Sets the texture for subsequent 3D draws.
    /// - Parameter img: The texture image.
    public func texture(_ img: MImage) {
        canvas3D.texture(img)
    }

    /// Removes the current texture.
    public func noTexture() {
        canvas3D.noTexture()
    }

    // MARK: - 3D Transform Stack

    /// Saves the transform matrix for both 2D and 3D canvases.
    public func pushMatrix() {
        canvas.pushMatrix()
        canvas3D.pushMatrix()
    }

    /// Restores the transform matrix for both 2D and 3D canvases.
    public func popMatrix() {
        canvas.popMatrix()
        canvas3D.popMatrix()
    }

    /// Applies a 3D translation.
    /// - Parameters:
    ///   - x: The x-axis translation.
    ///   - y: The y-axis translation.
    ///   - z: The z-axis translation.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.translate(x, y, z)
    }

    /// Rotates around the X axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) {
        canvas3D.rotateX(angle)
    }

    /// Rotates around the Y axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) {
        canvas3D.rotateY(angle)
    }

    /// Rotates around the Z axis.
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) {
        canvas3D.rotateZ(angle)
    }

    /// Applies a 3D scale.
    /// - Parameters:
    ///   - x: The x-axis scale factor.
    ///   - y: The y-axis scale factor.
    ///   - z: The z-axis scale factor.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.scale(x, y, z)
    }

    // MARK: - 3D Shapes

    /// Draws a box with the specified dimensions.
    /// - Parameters:
    ///   - width: The box width.
    ///   - height: The box height.
    ///   - depth: The box depth.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        canvas3D.box(width, height, depth)
    }

    /// Draws a uniform box (cube) with the given side length.
    /// - Parameter size: The side length.
    public func box(_ size: Float) {
        canvas3D.box(size)
    }

    /// Draws a sphere.
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - detail: The tessellation level (default 24).
    public func sphere(_ radius: Float, detail: Int = 24) {
        canvas3D.sphere(radius, detail: detail)
    }

    /// Draws a plane.
    /// - Parameters:
    ///   - width: The plane width.
    ///   - height: The plane height.
    public func plane(_ width: Float, _ height: Float) {
        canvas3D.plane(width, height)
    }

    /// Draws a cylinder.
    /// - Parameters:
    ///   - radius: The cylinder radius (default 0.5).
    ///   - height: The cylinder height (default 1).
    ///   - detail: The tessellation level (default 24).
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draws a cone.
    /// - Parameters:
    ///   - radius: The base radius (default 0.5).
    ///   - height: The cone height (default 1).
    ///   - detail: The tessellation level (default 24).
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cone(radius: radius, height: height, detail: detail)
    }

    /// Draws a torus.
    /// - Parameters:
    ///   - ringRadius: The ring (major) radius (default 0.5).
    ///   - tubeRadius: The tube (minor) radius (default 0.2).
    ///   - detail: The tessellation level (default 24).
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draws a pre-built mesh.
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) {
        canvas3D.mesh(mesh)
    }

    /// Draws a dynamic mesh.
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        canvas3D.dynamicMesh(mesh)
    }

    /// Creates an empty dynamic mesh for procedural geometry.
    /// - Returns: A new `DynamicMesh` instance.
    public func createDynamicMesh() -> DynamicMesh {
        DynamicMesh(device: renderer.device)
    }

    /// Loads a 3D model file (OBJ, USDZ, or ABC format).
    /// - Parameters:
    ///   - path: The file path to the model.
    ///   - normalize: Pass true to normalize the bounding box to [-1, 1] (default true).
    /// - Returns: The loaded mesh, or nil on failure.
    public func loadModel(_ path: String, normalize: Bool = true) -> Mesh? {
        let url = URL(fileURLWithPath: path)
        return try? Mesh.load(device: renderer.device, url: url, normalize: normalize)
    }

    // MARK: - Compute

    /// Creates a compute kernel from MSL source code.
    /// - Parameters:
    ///   - source: The MSL source code.
    ///   - function: The kernel function name.
    /// - Returns: A `ComputeKernel` instance.
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try ComputeKernel(device: renderer.device, source: source, functionName: function)
    }

    /// Creates a zero-initialized typed GPU buffer.
    /// - Parameters:
    ///   - count: The number of elements.
    ///   - type: The element type.
    /// - Returns: A new `GPUBuffer`, or nil on failure.
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, count: count)
    }

    /// Creates a GPU buffer from an array of data.
    /// - Parameter data: The source data array.
    /// - Returns: A new `GPUBuffer`, or nil on failure.
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, data: data)
    }

    /// Dispatches a 1D compute kernel.
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - threads: The total number of threads.
    ///   - configure: A closure to configure the compute encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: threads, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches a 2D compute kernel.
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - width: The grid width in threads.
    ///   - height: The grid height in threads.
    ///   - configure: A closure to configure the compute encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let h = max(1, kernel.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Inserts a memory barrier between compute dispatches to resolve data dependencies.
    public func computeBarrier() {
        _computeEncoder?.memoryBarrier(scope: .buffers)
    }

    /// Lazily creates and returns the compute command encoder.
    private func ensureComputeEncoder() -> MTLComputeCommandEncoder? {
        if let existing = _computeEncoder { return existing }
        guard let cb = _commandBuffer else { return nil }
        let encoder = cb.makeComputeCommandEncoder()
        _computeEncoder = encoder
        return encoder
    }

    // MARK: - Particle System

    /// Creates a GPU particle system.
    /// - Parameter count: The number of particles (default 100,000).
    /// - Returns: A `ParticleSystem` instance.
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try ParticleSystem(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            sampleCount: renderer.textureManager.sampleCount,
            count: count
        )
    }

    /// Updates a particle system (call during the compute phase).
    /// - Parameter system: The particle system to update.
    public func updateParticles(_ system: ParticleSystem) {
        guard let encoder = ensureComputeEncoder() else { return }
        system.update(encoder: encoder, deltaTime: deltaTime, time: time)
    }

    /// Draws a particle system (call during the draw phase).
    /// - Parameter system: The particle system to draw.
    public func drawParticles(_ system: ParticleSystem) {
        canvas.flush()
        guard let enc = canvas.currentEncoder else { return }
        system.draw(
            encoder: enc,
            viewProjection: canvas3D.currentViewProjection,
            cameraRight: canvas3D.currentCameraRight,
            cameraUp: canvas3D.currentCameraUp
        )
    }

    // MARK: - Audio

    /// Creates an audio input analyzer.
    /// - Parameter fftSize: The FFT window size (default 1024).
    /// - Returns: An `AudioAnalyzer` instance.
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        AudioAnalyzer(fftSize: fftSize)
    }

    // MARK: - OSC

    /// Creates an OSC receiver.
    /// - Parameter port: The UDP port number to listen on.
    /// - Returns: An `OSCReceiver` instance.
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        OSCReceiver(port: port)
    }

    // MARK: - Shader Hot Reload

    /// Recompiles shader source and clears the pipeline cache.
    ///
    /// Use in combination with `CustomMaterial.reload()` or `CustomPostEffect.reload()`.
    /// - Parameters:
    ///   - key: The shader library registration key.
    ///   - source: The new MSL source code.
    public func reloadShader(key: String, source: String) throws {
        try renderer.shaderLibrary.reload(key: key, source: source)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// Reloads a shader from an external file and clears the pipeline cache.
    /// - Parameters:
    ///   - key: The shader library registration key.
    ///   - path: The file path to the MSL source.
    public func reloadShaderFromFile(key: String, path: String) throws {
        try renderer.shaderLibrary.reloadFromFile(key: key, path: path)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// Creates a custom material from an external MSL file.
    /// - Parameters:
    ///   - path: The file path to the MSL source.
    ///   - fragmentFunction: The fragment shader function name.
    ///   - vertexFunction: An optional custom vertex shader function name.
    /// - Returns: A `CustomMaterial` instance.
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.registerFromFile(path: path, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw CustomMaterialError.shaderNotFound(fragmentFunction)
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw CustomMaterialError.shaderNotFound(vtxName)
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    // MARK: - Tween

    /// Creates a tween and registers it with the tween manager.
    /// - Parameters:
    ///   - from: The starting value.
    ///   - to: The ending value.
    ///   - duration: The tween duration in seconds.
    ///   - easing: The easing function (default ease-in-out cubic).
    /// - Returns: The created `Tween` instance.
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        let t = Tween(from: from, to: to, duration: duration, easing: easing)
        tweenManager.add(t)
        return t
    }

    // MARK: - Sound File (D-16)

    /// Loads an audio file from the specified path.
    /// - Parameter path: The file path to the audio file.
    /// - Returns: A `SoundFile` instance.
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }

    // MARK: - MIDI (D-17)

    /// Creates a MIDI manager for sending and receiving MIDI messages.
    /// - Returns: A `MIDIManager` instance.
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }

    // MARK: - GIF Export (D-19)

    /// The GIF exporter instance.
    public let gifExporter = GIFExporter()

    /// Begins GIF recording.
    /// - Parameter fps: The frame rate for the GIF (default 15).
    public func beginGIFRecord(fps: Int = 15) {
        gifExporter.beginRecord(
            fps: fps,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height
        )
    }

    /// Captures a GIF frame (called internally each frame).
    func captureGIFFrame() {
        guard gifExporter.isRecording else { return }
        gifExporter.captureFrame(
            texture: renderer.textureManager.colorTexture,
            device: renderer.device
        )
    }

    /// Ends GIF recording and writes the file.
    /// - Parameter path: The output file path (nil generates one on the Desktop automatically).
    public func endGIFRecord(_ path: String? = nil) throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try gifExporter.endRecord(to: actualPath)
    }

    // MARK: - Physics 2D

    /// Creates a 2D physics world.
    /// - Parameter cellSize: The spatial hash cell size (default 50).
    /// - Returns: A `Physics2D` instance.
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        Physics2D(cellSize: cellSize)
    }

    // MARK: - Orbit Camera (D-20)

    /// The orbit camera instance.
    public let orbitCamera = OrbitCamera()

    /// Enables orbit camera control (call during the draw phase).
    ///
    /// Drag the mouse to rotate the camera and scroll to zoom.
    public func orbitControl() {
        let inp = input

        // Rotate the camera on mouse drag
        if inp.isMouseDown {
            let dx = inp.mouseX - inp.pmouseX
            let dy = inp.mouseY - inp.pmouseY
            orbitCamera.handleMouseDrag(dx: dx, dy: dy)
        }

        // Zoom on scroll
        let sy = inp.scrollY
        if abs(sy) > 0.01 {
            orbitCamera.handleScroll(delta: sy)
        }

        // Update damping
        orbitCamera.update()

        // Apply to Canvas3D
        canvas3D.camera(eye: orbitCamera.eye, center: orbitCamera.target, up: orbitCamera.up)
    }

    // MARK: - Scene Graph

    /// Creates a scene graph node.
    /// - Parameter name: An optional name for the node.
    /// - Returns: A new `Node` instance.
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// Draws a scene graph starting from the root node.
    /// - Parameter root: The root node of the scene graph.
    public func drawScene(_ root: Node) {
        SceneRenderer.render(node: root, canvas: canvas3D)
    }

    // MARK: - Render Graph

    /// Creates a source pass for the render graph.
    /// - Parameters:
    ///   - label: The node label.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    /// - Returns: A `SourcePass` instance, or nil on failure.
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        try? SourcePass(
            label: label,
            device: renderer.device,
            width: width,
            height: height
        )
    }

    /// Creates an effect pass for the render graph.
    /// - Parameters:
    ///   - input: The input render pass node.
    ///   - effects: An array of post-processing effects.
    /// - Returns: An `EffectPass` instance, or nil on failure.
    public func createEffectPass(_ input: RenderPassNode, effects: [PostEffect]) -> EffectPass? {
        try? EffectPass(
            input,
            effects: effects,
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary
        )
    }

    /// Creates a merge pass that composites two render passes.
    /// - Parameters:
    ///   - a: The base pass.
    ///   - b: The overlay pass.
    ///   - blend: The blend type for compositing.
    /// - Returns: A `MergePass` instance, or nil on failure.
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        try? MergePass(
            a, b,
            blend: blend,
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary
        )
    }

    /// Sets the active render graph.
    /// - Parameter graph: The render graph to use, or nil to disable.
    public func setRenderGraph(_ graph: RenderGraph?) {
        renderer.renderGraph = graph
    }

    // MARK: - CoreML / Vision

    /// Creates a CoreML model processor.
    /// - Returns: An `MLProcessor` instance.
    public func createMLProcessor() -> MLProcessor {
        MLProcessor(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// Creates a Vision framework wrapper.
    /// - Returns: An `MLVision` instance.
    public func createVision() -> MLVision {
        MLVision(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// Creates a style transfer wrapper.
    /// - Returns: An `MLStyleTransfer` instance.
    public func createStyleTransfer() -> MLStyleTransfer {
        MLStyleTransfer(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// Loads a CoreML model from a file path and returns a configured processor.
    /// - Parameters:
    ///   - path: The file path to the CoreML model.
    ///   - computeUnit: The compute unit preference (default `.all`).
    /// - Returns: A loaded `MLProcessor` instance.
    public func loadMLModel(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        let processor = createMLProcessor()
        processor.computeUnit = computeUnit
        try processor.load(path)
        return processor
    }

    /// Loads a CoreML model from a bundle resource by name.
    /// - Parameters:
    ///   - name: The resource name of the CoreML model.
    ///   - computeUnit: The compute unit preference (default `.all`).
    /// - Returns: A loaded `MLProcessor` instance.
    public func loadMLModel(named name: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        let processor = createMLProcessor()
        processor.computeUnit = computeUnit
        try processor.load(named: name)
        return processor
    }

    /// Loads a style transfer model from a file path.
    /// - Parameters:
    ///   - path: The file path to the style transfer model.
    ///   - computeUnit: The compute unit preference (default `.all`).
    /// - Returns: A loaded `MLStyleTransfer` instance.
    public func loadStyleTransfer(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLStyleTransfer {
        let st = createStyleTransfer()
        try st.load(path, computeUnit: computeUnit)
        return st
    }

    /// Creates an ML texture converter for advanced texture-to-pixel-buffer conversions.
    /// - Returns: An `MLTextureConverter` instance.
    public func createMLTextureConverter() -> MLTextureConverter {
        MLTextureConverter(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    // MARK: - GameplayKit Noise

    /// Creates a GameplayKit noise generator.
    /// - Parameters:
    ///   - type: The noise type to generate.
    ///   - config: The noise configuration (default settings).
    /// - Returns: A `GKNoiseWrapper` instance.
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper {
        GKNoiseWrapper(type: type, config: config, device: renderer.device)
    }

    /// Generates a noise texture image as a convenience.
    /// - Parameters:
    ///   - type: The noise type to generate.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - config: The noise configuration (default settings).
    /// - Returns: The generated noise image, or nil on failure.
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        let noise = GKNoiseWrapper(type: type, config: config, device: renderer.device)
        return noise.image(width: width, height: height)
    }

    // MARK: - MPS Image Filter

    /// Creates an MPS image filter wrapper.
    /// - Returns: An `MPSImageFilterWrapper` instance.
    public func createMPSFilter() -> MPSImageFilterWrapper {
        MPSImageFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// Creates an MPS ray tracer.
    /// - Parameters:
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: An `MPSRayTracer` instance.
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(device: renderer.device, commandQueue: renderer.commandQueue, width: width, height: height)
    }

    // MARK: - CoreImage Filter

    /// The lazily initialized CoreImage filter wrapper.
    private var _ciFilterWrapper: CIFilterWrapper?

    /// Returns the shared CIFilterWrapper, creating it if needed.
    private func ensureCIFilterWrapper() -> CIFilterWrapper {
        if let wrapper = _ciFilterWrapper { return wrapper }
        let wrapper = CIFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
        _ciFilterWrapper = wrapper
        return wrapper
    }

    /// Applies a CoreImage filter to an image using a preset.
    /// - Parameters:
    ///   - image: The target image.
    ///   - preset: The filter preset to apply.
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        ensureCIFilterWrapper().apply(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(
                width: CGFloat(image.width), height: CGFloat(image.height)
            )),
            to: image
        )
    }

    /// Applies a CoreImage filter to an image by filter name.
    /// - Parameters:
    ///   - image: The target image.
    ///   - name: The CIFilter name.
    ///   - parameters: The filter parameters dictionary.
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        ensureCIFilterWrapper().apply(filterName: name, parameters: parameters, to: image)
    }

    /// Generates an image using a CoreImage generator filter.
    /// - Parameters:
    ///   - preset: The generator filter preset.
    ///   - width: The output width in pixels.
    ///   - height: The output height in pixels.
    /// - Returns: The generated image, or nil on failure.
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        guard let tex = ensureCIFilterWrapper().generate(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(width: width, height: height)),
            width: width,
            height: height
        ) else { return nil }
        return MImage(texture: tex)
    }
}
