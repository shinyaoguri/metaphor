#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@preconcurrency import Metal

/// Define a sketch by conforming to this protocol.
///
/// Annotate your class with `@main` and implement `draw()` to receive
/// automatic window, renderer, and Canvas2D setup. The `draw()` method
/// is called every frame.
///
/// ```swift
/// // Style A: Explicit context parameter
/// @main
/// final class MySketch: Sketch {
///     func draw(_ ctx: SketchContext) {
///         ctx.background(.black)
///         ctx.fill(.white)
///         ctx.circle(ctx.width / 2, ctx.height / 2, 200)
///     }
/// }
///
/// // Style B: No parameter (call drawing methods directly)
/// @main
/// final class MySketch: Sketch {
///     func draw() {
///         background(.black)
///         fill(.white)
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```
@MainActor
public protocol Sketch: AnyObject {
    /// Create a new instance with no arguments (required by `@main`).
    init()

    /// Return the configuration for this sketch (optional).
    var config: SketchConfig { get }

    /// Perform one-time initialization (optional).
    func setup()

    /// Draw a single frame using the provided context (implement one of the two `draw` variants).
    func draw(_ ctx: SketchContext)

    /// Draw a single frame without an explicit context (call drawing methods directly).
    func draw()

    /// Execute GPU compute work before each frame (optional).
    func compute()

    // MARK: - Input Events (all optional)

    /// Respond to a mouse button press.
    func mousePressed()

    /// Respond to a mouse button release.
    func mouseReleased()

    /// Respond to mouse movement.
    func mouseMoved()

    /// Respond to a mouse drag.
    func mouseDragged()

    /// Respond to a mouse scroll event.
    func mouseScrolled()

    /// Respond to a key press.
    func keyPressed()

    /// Respond to a key release.
    func keyReleased()
}

// MARK: - Active Context (internal global)

/// Store the active sketch context set by SketchRunner.
///
/// Thread safety is guaranteed by `@MainActor`, restricting access to the
/// main thread. Like Processing, p5.js, and openFrameworks, this library
/// uses a single-context model. Running multiple Sketch instances
/// simultaneously is not supported.
@MainActor
var _activeSketchContext: SketchContext?

// MARK: - Active Context Helper

extension Sketch {
    /// Retrieve the active context, raising a fatal error if called outside `setup()` or `draw()`.
    @MainActor
    fileprivate func activeContext(function: String = #function) -> SketchContext {
        guard let ctx = _activeSketchContext else {
            fatalError("[\(function)] must be called inside setup() or draw()")
        }
        return ctx
    }
}

// MARK: - Default Implementations

extension Sketch {
    public var config: SketchConfig { SketchConfig() }
    public func setup() {}
    public func draw(_ ctx: SketchContext) { draw() }
    public func draw() {}
    public func compute() {}
    public func mousePressed() {}
    public func mouseReleased() {}
    public func mouseMoved() {}
    public func mouseDragged() {}
    public func mouseScrolled() {}
    public func keyPressed() {}
    public func keyReleased() {}
}

// MARK: - Convenience Properties

extension Sketch {
    /// Return the canvas width in pixels.
    public var width: Float {
        _activeSketchContext?.width ?? 0
    }

    /// Return the canvas height in pixels.
    public var height: Float {
        _activeSketchContext?.height ?? 0
    }

    /// Access the input manager (use inside event handlers).
    public var input: InputManager {
        activeContext().input
    }

    /// Return the current mouse x-coordinate.
    public var mouseX: Float {
        _activeSketchContext?.input.mouseX ?? 0
    }

    /// Return the current mouse y-coordinate.
    public var mouseY: Float {
        _activeSketchContext?.input.mouseY ?? 0
    }

    /// Return the mouse x-coordinate from the previous frame.
    public var pmouseX: Float {
        _activeSketchContext?.input.pmouseX ?? 0
    }

    /// Return the mouse y-coordinate from the previous frame.
    public var pmouseY: Float {
        _activeSketchContext?.input.pmouseY ?? 0
    }

    /// Indicate whether a mouse button is currently pressed.
    public var isMousePressed: Bool {
        _activeSketchContext?.input.isMouseDown ?? false
    }

    /// Return the horizontal scroll amount for the current frame.
    public var scrollX: Float {
        _activeSketchContext?.input.scrollX ?? 0
    }

    /// Return the vertical scroll amount for the current frame.
    public var scrollY: Float {
        _activeSketchContext?.input.scrollY ?? 0
    }

    /// Return the currently pressed mouse button (0 = left, 1 = right, 2 = middle).
    public var mouseButton: Int {
        _activeSketchContext?.input.mouseButton ?? 0
    }

    /// Indicate whether a key is currently pressed.
    public var isKeyPressed: Bool {
        _activeSketchContext?.input.isKeyPressed ?? false
    }

    /// Return the last key that was pressed.
    public var key: Character? {
        _activeSketchContext?.input.lastKey
    }

    /// Return the key code of the last key that was pressed.
    public var keyCode: UInt16? {
        _activeSketchContext?.input.lastKeyCode
    }

    /// Return the elapsed time in seconds since the sketch started.
    public var time: Float {
        _activeSketchContext?.time ?? 0
    }

    /// Return the time elapsed since the previous frame in seconds.
    public var deltaTime: Float {
        _activeSketchContext?.deltaTime ?? 0
    }

    /// Return the total number of frames rendered so far.
    public var frameCount: Int {
        _activeSketchContext?.frameCount ?? 0
    }
}

// MARK: - Canvas Setup

extension Sketch {
    /// Set the canvas size (call inside `setup()`, p5.js-style).
    ///
    /// - Parameters:
    ///   - width: The canvas width in pixels.
    ///   - height: The canvas height in pixels.
    public func createCanvas(width: Int, height: Int) {
        _activeSketchContext?.createCanvas(width: width, height: height)
    }
}

// MARK: - Vector Factory

extension Sketch {
    /// Create a 2D vector (Processing PVector compatible).
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    /// - Returns: A new ``Vec2`` with the given components.
    public func createVector(_ x: Float = 0, _ y: Float = 0) -> Vec2 {
        Vec2(x, y)
    }

    /// Create a 3D vector (Processing PVector compatible).
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    ///   - z: The z component.
    /// - Returns: A new ``Vec3`` with the given components.
    public func createVector(_ x: Float, _ y: Float, _ z: Float) -> Vec3 {
        Vec3(x, y, z)
    }
}

// MARK: - Animation Control

extension Sketch {
    /// Indicate whether the animation loop is currently running.
    public var isLooping: Bool {
        _activeSketchContext?.isLooping ?? true
    }

    /// Resume the animation loop.
    public func loop() {
        _activeSketchContext?.loop()
    }

    /// Stop the animation loop.
    public func noLoop() {
        _activeSketchContext?.noLoop()
    }

    /// Render a single frame (use after calling ``noLoop()``).
    public func redraw() {
        _activeSketchContext?.redraw()
    }

    /// Change the frame rate dynamically.
    ///
    /// - Parameter fps: The target frames per second.
    public func frameRate(_ fps: Int) {
        _activeSketchContext?.frameRate(fps)
    }
}

// MARK: - Drawing Methods (context-free forwarding)

extension Sketch {

    // MARK: Shape Mode Settings

    /// Set the rectangle drawing mode.
    ///
    /// - Parameter mode: The rectangle interpretation mode.
    public func rectMode(_ mode: RectMode) {
        _activeSketchContext?.rectMode(mode)
    }

    /// Set the ellipse drawing mode.
    ///
    /// - Parameter mode: The ellipse interpretation mode.
    public func ellipseMode(_ mode: EllipseMode) {
        _activeSketchContext?.ellipseMode(mode)
    }

    /// Set the image drawing mode.
    ///
    /// - Parameter mode: The image interpretation mode.
    public func imageMode(_ mode: ImageMode) {
        _activeSketchContext?.imageMode(mode)
    }

    // MARK: Color Mode

    /// Set the color mode with per-channel maximums.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value for the first channel.
    ///   - max2: The maximum value for the second channel.
    ///   - max3: The maximum value for the third channel.
    ///   - maxA: The maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        _activeSketchContext?.colorMode(space, max1, max2, max3, maxA)
    }

    /// Set the color mode with a single maximum for all channels.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The maximum value for all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        _activeSketchContext?.colorMode(space, maxAll)
    }

    // MARK: Background

    /// Clear the canvas with the specified color.
    ///
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        _activeSketchContext?.background(color)
    }

    /// Clear the canvas with a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness (0 = black, 1 = white).
    public func background(_ gray: Float) {
        _activeSketchContext?.background(gray)
    }

    /// Clear the canvas with the specified color channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.background(v1, v2, v3, a)
    }

    // MARK: Style

    /// Set the fill color.
    ///
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        _activeSketchContext?.fill(color)
    }

    /// Set the fill color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.fill(v1, v2, v3, a)
    }

    /// Set the fill color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func fill(_ gray: Float) {
        _activeSketchContext?.fill(gray)
    }

    /// Set the fill color using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func fill(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.fill(gray, alpha)
    }

    /// Disable filling shapes.
    public func noFill() {
        _activeSketchContext?.noFill()
    }

    /// Set the stroke color.
    ///
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        _activeSketchContext?.stroke(color)
    }

    /// Set the stroke color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.stroke(v1, v2, v3, a)
    }

    /// Set the stroke color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func stroke(_ gray: Float) {
        _activeSketchContext?.stroke(gray)
    }

    /// Set the stroke color using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.stroke(gray, alpha)
    }

    /// Disable stroking shapes.
    public func noStroke() {
        _activeSketchContext?.noStroke()
    }

    /// Set the stroke weight (line thickness).
    ///
    /// - Parameter weight: The stroke width in pixels.
    public func strokeWeight(_ weight: Float) {
        _activeSketchContext?.strokeWeight(weight)
    }

    /// Set the stroke cap style.
    ///
    /// - Parameter cap: The line cap style.
    public func strokeCap(_ cap: StrokeCap) {
        _activeSketchContext?.strokeCap(cap)
    }

    /// Set the stroke join style.
    ///
    /// - Parameter join: The line join style.
    public func strokeJoin(_ join: StrokeJoin) {
        _activeSketchContext?.strokeJoin(join)
    }

    /// Set the blend mode for subsequent drawing operations.
    ///
    /// - Parameter mode: The blend mode to apply.
    public func blendMode(_ mode: BlendMode) {
        _activeSketchContext?.blendMode(mode)
    }

    // MARK: Tint

    /// Set the image tint color.
    ///
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) {
        _activeSketchContext?.tint(color)
    }

    /// Set the image tint color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.tint(v1, v2, v3, a)
    }

    /// Set the image tint using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func tint(_ gray: Float) {
        _activeSketchContext?.tint(gray)
    }

    /// Set the image tint using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func tint(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.tint(gray, alpha)
    }

    /// Remove the image tint.
    public func noTint() {
        _activeSketchContext?.noTint()
    }

    // MARK: Image

    /// Load an image from the specified file path.
    ///
    /// - Parameter path: The file path to the image.
    /// - Returns: The loaded image.
    public func loadImage(_ path: String) throws -> MImage {
        try activeContext().loadImage(path)
    }

    /// Create a blank image with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    /// - Returns: A new blank image, or `nil` if creation fails.
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        _activeSketchContext?.createImage(width, height)
    }

    /// Create a 2D offscreen graphics buffer.
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new ``Graphics`` instance, or `nil` if creation fails.
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        _activeSketchContext?.createGraphics(w, h)
    }

    /// Create a 3D offscreen graphics buffer.
    ///
    /// - Parameters:
    ///   - w: The buffer width in pixels.
    ///   - h: The buffer height in pixels.
    /// - Returns: A new ``Graphics3D`` instance, or `nil` if creation fails.
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        _activeSketchContext?.createGraphics3D(w, h)
    }

    /// Create a camera capture device.
    ///
    /// - Parameters:
    ///   - width: The capture width in pixels.
    ///   - height: The capture height in pixels.
    ///   - position: The camera position (front or back).
    /// - Returns: A new ``CaptureDevice`` instance, or `nil` if creation fails.
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice? {
        _activeSketchContext?.createCapture(width: width, height: height, position: position)
    }

    /// Draw the latest frame from a capture device at the specified position.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(capture, x, y)
    }

    /// Draw the latest frame from a capture device at the specified position and size.
    ///
    /// - Parameters:
    ///   - capture: The capture device to draw from.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(capture, x, y, w, h)
    }

    /// Draw a 2D offscreen graphics buffer at the specified position.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(pg, x, y)
    }

    /// Draw a 2D offscreen graphics buffer at the specified position and size.
    ///
    /// - Parameters:
    ///   - pg: The graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(pg, x, y, w, h)
    }

    /// Draw a 3D offscreen graphics buffer at the specified position.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(pg, x, y)
    }

    /// Draw a 3D offscreen graphics buffer at the specified position and size.
    ///
    /// - Parameters:
    ///   - pg: The 3D graphics buffer to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(pg, x, y, w, h)
    }

    /// Draw an image at the specified position.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(img, x, y)
    }

    /// Draw an image at the specified position and size.
    ///
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x-coordinate of the drawing position.
    ///   - y: The y-coordinate of the drawing position.
    ///   - w: The display width.
    ///   - h: The display height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(img, x, y, w, h)
    }

    /// Draw a sub-region of an image (for sprite sheets and tile maps).
    ///
    /// - Parameters:
    ///   - img: The source image.
    ///   - dx: The destination x-coordinate.
    ///   - dy: The destination y-coordinate.
    ///   - dw: The destination width.
    ///   - dh: The destination height.
    ///   - sx: The source region x-coordinate.
    ///   - sy: The source region y-coordinate.
    ///   - sw: The source region width.
    ///   - sh: The source region height.
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        _activeSketchContext?.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: Text

    /// Set the text size for subsequent text drawing.
    ///
    /// - Parameter size: The font size in points.
    public func textSize(_ size: Float) {
        _activeSketchContext?.textSize(size)
    }

    /// Set the font family for subsequent text drawing.
    ///
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) {
        _activeSketchContext?.textFont(family)
    }

    /// Set the text alignment.
    ///
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        _activeSketchContext?.textAlign(horizontal, vertical)
    }

    /// Set the line spacing for multiline text.
    ///
    /// - Parameter leading: The line height in pixels.
    public func textLeading(_ leading: Float) {
        _activeSketchContext?.textLeading(leading)
    }

    /// Draw a text string at the specified position.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        _activeSketchContext?.text(string, x, y)
    }

    /// Draw a text string within a bounding box.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x-coordinate of the bounding box.
    ///   - y: The y-coordinate of the bounding box.
    ///   - w: The width of the bounding box.
    ///   - h: The height of the bounding box.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.text(string, x, y, w, h)
    }

    /// Calculate the width of a text string using the current font settings.
    ///
    /// - Parameter string: The text to measure.
    /// - Returns: The width of the text in pixels.
    public func textWidth(_ string: String) -> Float {
        _activeSketchContext?.textWidth(string) ?? 0
    }

    /// Return the ascent of the current font.
    ///
    /// - Returns: The ascent value in pixels.
    public func textAscent() -> Float {
        _activeSketchContext?.textAscent() ?? 0
    }

    /// Return the descent of the current font.
    ///
    /// - Returns: The descent value in pixels.
    public func textDescent() -> Float {
        _activeSketchContext?.textDescent() ?? 0
    }

    // MARK: Screenshot & Recording

    /// Save the current frame to the specified file path.
    ///
    /// - Parameter path: The output file path.
    public func save(_ path: String) {
        _activeSketchContext?.save(path)
    }

    /// Save the current frame to the default location.
    public func save() {
        _activeSketchContext?.save()
    }

    /// Begin recording a sequence of frames as image files.
    ///
    /// - Parameters:
    ///   - directory: The output directory (uses a default if `nil`).
    ///   - pattern: The filename pattern with a frame number placeholder.
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        _activeSketchContext?.beginRecord(directory: directory, pattern: pattern)
    }

    /// Stop recording the frame sequence.
    public func endRecord() {
        _activeSketchContext?.endRecord()
    }

    /// Save a single frame to an image file.
    ///
    /// - Parameter filename: The output filename (auto-generated if `nil`).
    public func saveFrame(_ filename: String? = nil) {
        _activeSketchContext?.saveFrame(filename)
    }

    // MARK: Video Recording

    /// Begin recording video output.
    ///
    /// - Parameters:
    ///   - path: The output file path (auto-generated if `nil`).
    ///   - config: The video export configuration.
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        _activeSketchContext?.beginVideoRecord(path, config: config)
    }

    /// Stop recording video and finalize the file.
    ///
    /// - Parameter completion: An optional callback invoked when writing finishes.
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        _activeSketchContext?.endVideoRecord(completion: completion)
    }

    // MARK: Offline Rendering

    /// Indicate whether offline rendering mode is active.
    public var isOfflineRendering: Bool {
        _activeSketchContext?.isOfflineRendering ?? false
    }

    /// Enable offline rendering mode with deterministic timing.
    ///
    /// - Parameter fps: The virtual frame rate used for time calculation.
    public func beginOfflineRender(fps: Double = 60) {
        _activeSketchContext?.beginOfflineRender(fps: fps)
    }

    /// Disable offline rendering mode and return to real-time timing.
    public func endOfflineRender() {
        _activeSketchContext?.endOfflineRender()
    }

    // MARK: FBO Feedback

    /// Enable framebuffer feedback (previous frame access).
    public func enableFeedback() {
        _activeSketchContext?.enableFeedback()
    }

    /// Disable framebuffer feedback.
    public func disableFeedback() {
        _activeSketchContext?.disableFeedback()
    }

    /// Retrieve the previous frame's rendered image.
    ///
    /// - Returns: The previous frame as an ``MImage``, or `nil` if feedback is disabled.
    public func previousFrame() -> MImage? {
        _activeSketchContext?.previousFrame()
    }

    // MARK: 2D Transform Stack

    /// Save the current transform and style state onto the stack.
    public func push() {
        _activeSketchContext?.push()
    }

    /// Restore the most recently saved transform and style state from the stack.
    public func pop() {
        _activeSketchContext?.pop()
    }

    /// Save the current style state (fill, stroke, etc.) onto the stack.
    public func pushStyle() {
        _activeSketchContext?.pushStyle()
    }

    /// Restore the most recently saved style state from the stack.
    public func popStyle() {
        _activeSketchContext?.popStyle()
    }

    /// Apply a 2D translation to the current transform.
    ///
    /// - Parameters:
    ///   - x: The horizontal translation amount.
    ///   - y: The vertical translation amount.
    public func translate(_ x: Float, _ y: Float) {
        _activeSketchContext?.translate(x, y)
    }

    /// Apply a 2D rotation to the current transform.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) {
        _activeSketchContext?.rotate(angle)
    }

    /// Apply a non-uniform 2D scale to the current transform.
    ///
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) {
        _activeSketchContext?.scale(sx, sy)
    }

    /// Apply a uniform 2D scale to the current transform.
    ///
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) {
        _activeSketchContext?.scale(s)
    }

    // MARK: 2D Shapes

    /// Draw a rectangle.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.rect(x, y, w, h)
    }

    /// Draw a rounded rectangle with a uniform corner radius.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - r: The corner radius.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        _activeSketchContext?.rect(x, y, w, h, r)
    }

    /// Draw a rounded rectangle with individual corner radii.
    ///
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
        _activeSketchContext?.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// Draw a linear gradient rectangle.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - c1: The start color.
    ///   - c2: The end color.
    ///   - axis: The gradient direction.
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        _activeSketchContext?.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// Draw a radial gradient circle.
    ///
    /// - Parameters:
    ///   - cx: The center x-coordinate.
    ///   - cy: The center y-coordinate.
    ///   - radius: The outer radius.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the edge.
    ///   - segments: The number of segments for smoothness.
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        _activeSketchContext?.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// Draw an ellipse.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width (horizontal diameter).
    ///   - h: The height (vertical diameter).
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.ellipse(x, y, w, h)
    }

    /// Draw a circle.
    ///
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - diameter: The diameter of the circle.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        _activeSketchContext?.circle(x, y, diameter)
    }

    /// Draw a square.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - size: The side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        _activeSketchContext?.square(x, y, size)
    }

    /// Draw a quadrilateral defined by four corner points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first corner.
    ///   - y1: The y-coordinate of the first corner.
    ///   - x2: The x-coordinate of the second corner.
    ///   - y2: The y-coordinate of the second corner.
    ///   - x3: The x-coordinate of the third corner.
    ///   - y3: The y-coordinate of the third corner.
    ///   - x4: The x-coordinate of the fourth corner.
    ///   - y4: The y-coordinate of the fourth corner.
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        _activeSketchContext?.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Draw a line between two points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the start point.
    ///   - y1: The y-coordinate of the start point.
    ///   - x2: The x-coordinate of the end point.
    ///   - y2: The y-coordinate of the end point.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        _activeSketchContext?.line(x1, y1, x2, y2)
    }

    /// Draw a triangle defined by three corner points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first corner.
    ///   - y1: The y-coordinate of the first corner.
    ///   - x2: The x-coordinate of the second corner.
    ///   - y2: The y-coordinate of the second corner.
    ///   - x3: The x-coordinate of the third corner.
    ///   - y3: The y-coordinate of the third corner.
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        _activeSketchContext?.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// Draw a polygon from an array of coordinate tuples.
    ///
    /// - Parameter points: The polygon vertices as `(x, y)` tuples.
    public func polygon(_ points: [(Float, Float)]) {
        _activeSketchContext?.polygon(points)
    }

    /// Draw a polygon from an array of ``Vec2`` points.
    ///
    /// - Parameter points: The polygon vertices.
    public func polygon(_ points: [Vec2]) {
        _activeSketchContext?.polygon(points)
    }

    /// Draw an arc.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the arc center.
    ///   - y: The y-coordinate of the arc center.
    ///   - w: The width of the arc's bounding ellipse.
    ///   - h: The height of the arc's bounding ellipse.
    ///   - startAngle: The start angle in radians.
    ///   - stopAngle: The stop angle in radians.
    ///   - mode: The arc drawing mode.
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        _activeSketchContext?.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// Draw a cubic Bezier curve.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the start point.
    ///   - y1: The y-coordinate of the start point.
    ///   - cx1: The x-coordinate of the first control point.
    ///   - cy1: The y-coordinate of the first control point.
    ///   - cx2: The x-coordinate of the second control point.
    ///   - cy2: The y-coordinate of the second control point.
    ///   - x2: The x-coordinate of the end point.
    ///   - y2: The y-coordinate of the end point.
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        _activeSketchContext?.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// Draw a single point.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func point(_ x: Float, _ y: Float) {
        _activeSketchContext?.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    /// Begin recording vertices for a custom shape.
    ///
    /// - Parameter mode: The shape mode (e.g., polygon, triangles, lines).
    public func beginShape(_ mode: ShapeMode = .polygon) {
        _activeSketchContext?.beginShape(mode)
    }

    /// Add a 2D vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func vertex(_ x: Float, _ y: Float) {
        _activeSketchContext?.vertex(x, y)
    }

    /// Add a 2D vertex with a per-vertex color to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        _activeSketchContext?.vertex(x, y, color)
    }

    /// Add a 2D vertex with texture coordinates to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - u: The horizontal texture coordinate.
    ///   - v: The vertical texture coordinate.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        _activeSketchContext?.vertex(x, y, u, v)
    }

    /// Add a cubic Bezier vertex to the current shape.
    ///
    /// - Parameters:
    ///   - cx1: The x-coordinate of the first control point.
    ///   - cy1: The y-coordinate of the first control point.
    ///   - cx2: The x-coordinate of the second control point.
    ///   - cy2: The y-coordinate of the second control point.
    ///   - x: The x-coordinate of the anchor point.
    ///   - y: The y-coordinate of the anchor point.
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        _activeSketchContext?.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Add a Catmull-Rom spline vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func curveVertex(_ x: Float, _ y: Float) {
        _activeSketchContext?.curveVertex(x, y)
    }

    /// Set the number of segments used for curve interpolation.
    ///
    /// - Parameter n: The curve detail level.
    public func curveDetail(_ n: Int) {
        _activeSketchContext?.curveDetail(n)
    }

    /// Set the tightness of Catmull-Rom spline curves.
    ///
    /// - Parameter t: The tightness value (0 = default, 1 = straight lines).
    public func curveTightness(_ t: Float) {
        _activeSketchContext?.curveTightness(t)
    }

    /// Begin defining a contour (hole) within the current shape.
    public func beginContour() {
        _activeSketchContext?.beginContour()
    }

    /// End the current contour definition.
    public func endContour() {
        _activeSketchContext?.endContour()
    }

    /// Draw a Catmull-Rom spline curve through four points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first control point.
    ///   - y1: The y-coordinate of the first control point.
    ///   - x2: The x-coordinate of the start point.
    ///   - y2: The y-coordinate of the start point.
    ///   - x3: The x-coordinate of the end point.
    ///   - y3: The y-coordinate of the end point.
    ///   - x4: The x-coordinate of the second control point.
    ///   - y4: The y-coordinate of the second control point.
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        _activeSketchContext?.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Finish recording the current shape and draw it.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape(_ close: CloseMode = .open) {
        _activeSketchContext?.endShape(close)
    }

    // MARK: 3D Custom Shapes

    /// Begin recording vertices for a 3D custom shape.
    ///
    /// - Parameter mode: The shape mode (e.g., polygon, triangles, lines).
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        _activeSketchContext?.beginShape3D(mode)
    }

    /// Add a 3D vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.vertex(x, y, z)
    }

    /// Add a 3D vertex with a per-vertex color to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - z: The z-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        _activeSketchContext?.vertex(x, y, z, color)
    }

    /// Set the normal vector for subsequent 3D vertices.
    ///
    /// - Parameters:
    ///   - nx: The x-component of the normal.
    ///   - ny: The y-component of the normal.
    ///   - nz: The z-component of the normal.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        _activeSketchContext?.normal(nx, ny, nz)
    }

    /// Finish recording the current 3D shape and draw it.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape3D(_ close: CloseMode = .open) {
        _activeSketchContext?.endShape3D(close)
    }

    // MARK: 3D Camera

    /// Set the 3D camera using eye, center, and up vectors.
    ///
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector.
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        _activeSketchContext?.camera(eye: eye, center: center, up: up)
    }

    /// Set the 3D camera using individual float components.
    ///
    /// - Parameters:
    ///   - eyeX: The x-coordinate of the camera position.
    ///   - eyeY: The y-coordinate of the camera position.
    ///   - eyeZ: The z-coordinate of the camera position.
    ///   - centerX: The x-coordinate of the look-at target.
    ///   - centerY: The y-coordinate of the look-at target.
    ///   - centerZ: The z-coordinate of the look-at target.
    ///   - upX: The x-component of the up vector.
    ///   - upY: The y-component of the up vector.
    ///   - upZ: The z-component of the up vector.
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        _activeSketchContext?.camera(eyeX, eyeY, eyeZ, centerX, centerY, centerZ, upX, upY, upZ)
    }

    /// Set the perspective projection.
    ///
    /// - Parameters:
    ///   - fov: The field of view angle in radians.
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        _activeSketchContext?.perspective(fov: fov, near: near, far: far)
    }

    /// Set the orthographic projection.
    ///
    /// - Parameters:
    ///   - left: The left clipping plane (defaults to canvas bounds).
    ///   - right: The right clipping plane (defaults to canvas bounds).
    ///   - bottom: The bottom clipping plane (defaults to canvas bounds).
    ///   - top: The top clipping plane (defaults to canvas bounds).
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        _activeSketchContext?.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    /// Enable default lighting (a directional light and ambient light).
    public func lights() {
        _activeSketchContext?.lights()
    }

    /// Disable all lights.
    public func noLights() {
        _activeSketchContext?.noLights()
    }

    /// Add a directional light with the default color.
    ///
    /// - Parameters:
    ///   - x: The x-component of the light direction.
    ///   - y: The y-component of the light direction.
    ///   - z: The z-component of the light direction.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.directionalLight(x, y, z)
    }

    /// Add a directional light with a specified color.
    ///
    /// - Parameters:
    ///   - x: The x-component of the light direction.
    ///   - y: The y-component of the light direction.
    ///   - z: The z-component of the light direction.
    ///   - color: The light color.
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        _activeSketchContext?.directionalLight(x, y, z, color: color)
    }

    /// Add a point light at the specified position.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the light position.
    ///   - y: The y-coordinate of the light position.
    ///   - z: The z-coordinate of the light position.
    ///   - color: The light color.
    ///   - falloff: The attenuation factor.
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        _activeSketchContext?.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// Add a spot light at the specified position pointing in the given direction.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the light position.
    ///   - y: The y-coordinate of the light position.
    ///   - z: The z-coordinate of the light position.
    ///   - dirX: The x-component of the light direction.
    ///   - dirY: The y-component of the light direction.
    ///   - dirZ: The z-component of the light direction.
    ///   - angle: The cone angle in radians.
    ///   - falloff: The attenuation factor.
    ///   - color: The light color.
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        _activeSketchContext?.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// Set the ambient light intensity using a single grayscale value.
    ///
    /// - Parameter strength: The ambient light strength.
    public func ambientLight(_ strength: Float) {
        _activeSketchContext?.ambientLight(strength)
    }

    /// Set the ambient light color using RGB values.
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        _activeSketchContext?.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// Enable shadow mapping.
    ///
    /// - Parameter resolution: The shadow map resolution in pixels.
    public func enableShadows(resolution: Int = 2048) {
        _activeSketchContext?.enableShadows(resolution: resolution)
    }

    /// Disable shadow mapping.
    public func disableShadows() {
        _activeSketchContext?.disableShadows()
    }

    /// Set the shadow depth bias to reduce shadow acne.
    ///
    /// - Parameter value: The bias value.
    public func shadowBias(_ value: Float) {
        _activeSketchContext?.shadowBias(value)
    }

    // MARK: 3D Material

    /// Set the specular highlight color.
    ///
    /// - Parameter color: The specular color.
    public func specular(_ color: Color) {
        _activeSketchContext?.specular(color)
    }

    /// Set the specular highlight color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func specular(_ gray: Float) {
        _activeSketchContext?.specular(gray)
    }

    /// Set the specular shininess exponent.
    ///
    /// - Parameter value: The shininess value (higher values produce smaller highlights).
    public func shininess(_ value: Float) {
        _activeSketchContext?.shininess(value)
    }

    /// Set the emissive (self-illumination) color.
    ///
    /// - Parameter color: The emissive color.
    public func emissive(_ color: Color) {
        _activeSketchContext?.emissive(color)
    }

    /// Set the emissive color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func emissive(_ gray: Float) {
        _activeSketchContext?.emissive(gray)
    }

    /// Set the metallic factor for the material.
    ///
    /// - Parameter value: The metallic value (0 = dielectric, 1 = metal).
    public func metallic(_ value: Float) {
        _activeSketchContext?.metallic(value)
    }

    /// Set the PBR roughness (automatically enables PBR mode).
    ///
    /// - Parameter value: The roughness value (0 = smooth, 1 = rough).
    public func roughness(_ value: Float) {
        _activeSketchContext?.roughness(value)
    }

    /// Set the PBR ambient occlusion factor.
    ///
    /// - Parameter value: The ambient occlusion value (0 = fully occluded, 1 = none).
    public func ambientOcclusion(_ value: Float) {
        _activeSketchContext?.ambientOcclusion(value)
    }

    /// Toggle PBR rendering mode explicitly.
    ///
    /// - Parameter enabled: Whether to enable PBR rendering.
    public func pbr(_ enabled: Bool) {
        _activeSketchContext?.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// Create a custom shader material from MSL source code.
    ///
    /// - Parameters:
    ///   - source: The Metal Shading Language source code.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The optional name of a custom vertex function.
    /// - Returns: A new ``CustomMaterial`` instance.
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterial(source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// Apply a custom material to subsequent 3D draws.
    ///
    /// - Parameter customMaterial: The custom material to apply.
    public func material(_ customMaterial: CustomMaterial) {
        _activeSketchContext?.material(customMaterial)
    }

    /// Remove the active custom material and return to the default shading.
    public func noMaterial() {
        _activeSketchContext?.noMaterial()
    }

    // MARK: 3D Texture

    /// Set the texture for subsequent 3D shapes.
    ///
    /// - Parameter img: The texture image.
    public func texture(_ img: MImage) {
        _activeSketchContext?.texture(img)
    }

    /// Remove the active texture.
    public func noTexture() {
        _activeSketchContext?.noTexture()
    }

    // MARK: 3D Transform Stack

    /// Save the current 3D transformation matrix onto the stack.
    public func pushMatrix() {
        _activeSketchContext?.pushMatrix()
    }

    /// Restore the most recently saved 3D transformation matrix from the stack.
    public func popMatrix() {
        _activeSketchContext?.popMatrix()
    }

    /// Apply a 3D translation to the current transform.
    ///
    /// - Parameters:
    ///   - x: The translation along the x-axis.
    ///   - y: The translation along the y-axis.
    ///   - z: The translation along the z-axis.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.translate(x, y, z)
    }

    /// Apply a rotation around the x-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateX(_ angle: Float) {
        _activeSketchContext?.rotateX(angle)
    }

    /// Apply a rotation around the y-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateY(_ angle: Float) {
        _activeSketchContext?.rotateY(angle)
    }

    /// Apply a rotation around the z-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotateZ(_ angle: Float) {
        _activeSketchContext?.rotateZ(angle)
    }

    /// Apply a non-uniform 3D scale to the current transform.
    ///
    /// - Parameters:
    ///   - x: The scale factor along the x-axis.
    ///   - y: The scale factor along the y-axis.
    ///   - z: The scale factor along the z-axis.
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.scale(x, y, z)
    }

    // MARK: 3D Shapes

    /// Draw a box with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The width of the box.
    ///   - height: The height of the box.
    ///   - depth: The depth of the box.
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        _activeSketchContext?.box(width, height, depth)
    }

    /// Draw a cube with equal side lengths.
    ///
    /// - Parameter size: The side length.
    public func box(_ size: Float) {
        _activeSketchContext?.box(size)
    }

    /// Draw a sphere.
    ///
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - detail: The number of subdivisions for mesh tessellation.
    public func sphere(_ radius: Float, detail: Int = 24) {
        _activeSketchContext?.sphere(radius, detail: detail)
    }

    /// Draw a flat plane.
    ///
    /// - Parameters:
    ///   - width: The plane width.
    ///   - height: The plane height.
    public func plane(_ width: Float, _ height: Float) {
        _activeSketchContext?.plane(width, height)
    }

    /// Draw a cylinder.
    ///
    /// - Parameters:
    ///   - radius: The cylinder radius.
    ///   - height: The cylinder height.
    ///   - detail: The number of subdivisions around the circumference.
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _activeSketchContext?.cylinder(radius: radius, height: height, detail: detail)
    }

    /// Draw a cone.
    ///
    /// - Parameters:
    ///   - radius: The base radius.
    ///   - height: The cone height.
    ///   - detail: The number of subdivisions around the circumference.
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _activeSketchContext?.cone(radius: radius, height: height, detail: detail)
    }

    /// Draw a torus (donut shape).
    ///
    /// - Parameters:
    ///   - ringRadius: The distance from the center of the torus to the center of the tube.
    ///   - tubeRadius: The radius of the tube.
    ///   - detail: The number of subdivisions.
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        _activeSketchContext?.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// Draw a prebuilt mesh.
    ///
    /// - Parameter mesh: The mesh to draw.
    public func mesh(_ mesh: Mesh) {
        _activeSketchContext?.mesh(mesh)
    }

    /// Draw a dynamic mesh.
    ///
    /// - Parameter mesh: The dynamic mesh to draw.
    public func dynamicMesh(_ mesh: DynamicMesh) {
        _activeSketchContext?.dynamicMesh(mesh)
    }

    /// Create a new empty dynamic mesh.
    ///
    /// - Returns: A new ``DynamicMesh`` instance.
    public func createDynamicMesh() -> DynamicMesh {
        activeContext().createDynamicMesh()
    }

    /// Load a 3D model from a file (OBJ, USDZ, ABC).
    ///
    /// - Parameter path: The file path to the model.
    /// - Returns: The loaded mesh, or `nil` if loading fails.
    public func loadModel(_ path: String) -> Mesh? {
        _activeSketchContext?.loadModel(path)
    }

    // MARK: Compute

    /// Create a GPU compute kernel from MSL source code.
    ///
    /// - Parameters:
    ///   - source: The Metal Shading Language source code.
    ///   - function: The name of the compute function.
    /// - Returns: A new ``ComputeKernel`` instance.
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try activeContext().createComputeKernel(source: source, function: function)
    }

    /// Create a GPU buffer with the specified element count and type.
    ///
    /// - Parameters:
    ///   - count: The number of elements.
    ///   - type: The element type.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        _activeSketchContext?.createBuffer(count: count, type: type)
    }

    /// Create a GPU buffer initialized with the given data.
    ///
    /// - Parameter data: The initial data array.
    /// - Returns: A new ``GPUBuffer``, or `nil` if creation fails.
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        _activeSketchContext?.createBuffer(data)
    }

    /// Dispatch a 1D compute kernel.
    ///
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - threads: The total number of threads.
    ///   - configure: A closure to configure the compute command encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _activeSketchContext?.dispatch(kernel, threads: threads, configure)
    }

    /// Dispatch a 2D compute kernel.
    ///
    /// - Parameters:
    ///   - kernel: The compute kernel to dispatch.
    ///   - width: The grid width in threads.
    ///   - height: The grid height in threads.
    ///   - configure: A closure to configure the compute command encoder before dispatch.
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _activeSketchContext?.dispatch(kernel, width: width, height: height, configure)
    }

    /// Insert a barrier in the compute command encoder to synchronize dispatches.
    public func computeBarrier() {
        _activeSketchContext?.computeBarrier()
    }
}

// MARK: - Particle System

extension Sketch {
    /// Create a GPU particle system.
    ///
    /// - Parameter count: The maximum number of particles.
    /// - Returns: A new ``ParticleSystem`` instance.
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try activeContext().createParticleSystem(count: count)
    }

    /// Update a particle system (call inside ``compute()``).
    ///
    /// - Parameter system: The particle system to update.
    public func updateParticles(_ system: ParticleSystem) {
        _activeSketchContext?.updateParticles(system)
    }

    /// Draw a particle system (call inside ``draw()``).
    ///
    /// - Parameter system: The particle system to draw.
    public func drawParticles(_ system: ParticleSystem) {
        _activeSketchContext?.drawParticles(system)
    }
}

// MARK: - Audio

extension Sketch {
    /// Create an audio input analyzer for real-time FFT and beat detection.
    ///
    /// - Parameter fftSize: The FFT window size (must be a power of two).
    /// - Returns: A new ``AudioAnalyzer`` instance.
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        activeContext().createAudioInput(fftSize: fftSize)
    }
}

// MARK: - OSC

extension Sketch {
    /// Create an OSC (Open Sound Control) receiver.
    ///
    /// - Parameter port: The UDP port to listen on.
    /// - Returns: A new ``OSCReceiver`` instance.
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        activeContext().createOSCReceiver(port: port)
    }
}

// MARK: - Tween

extension Sketch {
    /// Create and register a tween animation (automatically added to the tween manager).
    ///
    /// - Parameters:
    ///   - from: The start value.
    ///   - to: The end value.
    ///   - duration: The animation duration in seconds.
    ///   - easing: The easing function.
    /// - Returns: A new ``Tween`` instance.
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        activeContext().tween(from: from, to: to, duration: duration, easing: easing)
    }
}

// MARK: - Shader Hot Reload

extension Sketch {
    /// Recompile a shader from source and clear the pipeline cache.
    ///
    /// - Parameters:
    ///   - key: The shader library key to reload.
    ///   - source: The new MSL source code.
    public func reloadShader(key: String, source: String) throws {
        try activeContext().reloadShader(key: key, source: source)
    }

    /// Reload a shader from an external file and clear the pipeline cache.
    ///
    /// - Parameters:
    ///   - key: The shader library key to reload.
    ///   - path: The file path to the MSL source file.
    public func reloadShaderFromFile(key: String, path: String) throws {
        try activeContext().reloadShaderFromFile(key: key, path: path)
    }

    /// Create a custom material by loading MSL source from an external file.
    ///
    /// - Parameters:
    ///   - path: The file path to the MSL source file.
    ///   - fragmentFunction: The name of the fragment function.
    ///   - vertexFunction: The optional name of a custom vertex function.
    /// - Returns: A new ``CustomMaterial`` instance.
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterialFromFile(path: path, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }
}

// MARK: - GUI

extension Sketch {
    /// Access the parameter GUI for creating immediate-mode UI controls.
    public var gui: ParameterGUI {
        activeContext().gui
    }
}

// MARK: - Performance HUD

extension Sketch {
    /// Enable the performance heads-up display overlay.
    public func enablePerformanceHUD() {
        _activeSketchContext?.enablePerformanceHUD()
    }

    /// Disable the performance heads-up display overlay.
    public func disablePerformanceHUD() {
        _activeSketchContext?.disablePerformanceHUD()
    }
}

// MARK: - Post Process

extension Sketch {
    /// Create a custom post-processing effect from MSL source code.
    ///
    /// - Parameters:
    ///   - name: The display name for the effect.
    ///   - source: The Metal Shading Language source code.
    ///   - fragmentFunction: The name of the fragment function.
    /// - Returns: A new ``CustomPostEffect`` instance.
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        try activeContext().createPostEffect(name: name, source: source, fragmentFunction: fragmentFunction)
    }

    /// Add a post-processing effect to the pipeline.
    ///
    /// - Parameter effect: The post-processing effect to add.
    public func addPostEffect(_ effect: PostEffect) {
        _activeSketchContext?.addPostEffect(effect)
    }

    /// Remove a post-processing effect at the specified index.
    ///
    /// - Parameter index: The index of the effect to remove.
    public func removePostEffect(at index: Int) {
        _activeSketchContext?.removePostEffect(at: index)
    }

    /// Remove all post-processing effects from the pipeline.
    public func clearPostEffects() {
        _activeSketchContext?.clearPostEffects()
    }

    /// Replace all post-processing effects with the given array.
    ///
    /// - Parameter effects: The new array of post-processing effects.
    public func setPostEffects(_ effects: [PostEffect]) {
        _activeSketchContext?.setPostEffects(effects)
    }
}

// MARK: - Cursor Control

extension Sketch {
    /// Show the cursor.
    public func cursor() {
        _activeSketchContext?.cursor()
    }

    /// Hide the cursor.
    public func noCursor() {
        _activeSketchContext?.noCursor()
    }
}

// MARK: - Sound File (D-16)

extension Sketch {
    /// Load an audio file for playback and analysis.
    ///
    /// - Parameter path: The file path to the audio file.
    /// - Returns: A new ``SoundFile`` instance.
    public func loadSound(_ path: String) throws -> SoundFile {
        try activeContext().loadSound(path)
    }
}

// MARK: - MIDI (D-17)

extension Sketch {
    /// Create a MIDI manager for input and output.
    ///
    /// - Returns: A new ``MIDIManager`` instance.
    public func createMIDI() -> MIDIManager {
        activeContext().createMIDI()
    }
}

// MARK: - GIF Export (D-19)

extension Sketch {
    /// Begin recording frames for GIF export.
    ///
    /// - Parameter fps: The target frames per second for the GIF.
    public func beginGIFRecord(fps: Int = 15) {
        _activeSketchContext?.beginGIFRecord(fps: fps)
    }

    /// Stop recording and write the GIF to a file.
    ///
    /// - Parameter path: The output file path (auto-generated if `nil`).
    public func endGIFRecord(_ path: String? = nil) throws {
        try activeContext().endGIFRecord(path)
    }
}

// MARK: - Physics 2D

extension Sketch {
    /// Create a 2D physics simulation world.
    ///
    /// - Parameter cellSize: The spatial hash cell size for broad-phase collision detection.
    /// - Returns: A new ``Physics2D`` instance.
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        Physics2D(cellSize: cellSize)
    }
}

// MARK: - Orbit Camera (D-20)

extension Sketch {
    /// Enable orbit camera controls (call inside ``draw()``).
    public func orbitControl() {
        _activeSketchContext?.orbitControl()
    }

    /// Access the orbit camera for manual configuration.
    public var orbitCamera: OrbitCamera {
        activeContext().orbitCamera
    }
}

// MARK: - Scene Graph

extension Sketch {
    /// Create a scene graph node.
    ///
    /// - Parameter name: The optional name for the node.
    /// - Returns: A new ``Node`` instance.
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// Draw a scene graph starting from the specified root node.
    ///
    /// - Parameter root: The root node of the scene graph to render.
    public func drawScene(_ root: Node) {
        _activeSketchContext?.drawScene(root)
    }
}

// MARK: - Render Graph

extension Sketch {
    /// Create a source pass for the render graph.
    ///
    /// - Parameters:
    ///   - label: The debug label for the pass.
    ///   - width: The render target width in pixels.
    ///   - height: The render target height in pixels.
    /// - Returns: A new ``SourcePass`` instance, or `nil` if creation fails.
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        _activeSketchContext?.createSourcePass(label: label, width: width, height: height)
    }

    /// Create an effect pass that applies post-processing effects to a render pass.
    ///
    /// - Parameters:
    ///   - input: The input render pass node.
    ///   - effects: The post-processing effects to apply.
    /// - Returns: A new ``EffectPass`` instance, or `nil` if creation fails.
    public func createEffectPass(_ input: RenderPassNode, effects: [PostEffect]) -> EffectPass? {
        _activeSketchContext?.createEffectPass(input, effects: effects)
    }

    /// Create a merge pass that combines two render passes.
    ///
    /// - Parameters:
    ///   - a: The first input render pass node.
    ///   - b: The second input render pass node.
    ///   - blend: The blend type for compositing.
    /// - Returns: A new ``MergePass`` instance, or `nil` if creation fails.
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        _activeSketchContext?.createMergePass(a, b, blend: blend)
    }

    /// Set or clear the active render graph.
    ///
    /// - Parameter graph: The render graph to use, or `nil` to disable.
    public func setRenderGraph(_ graph: RenderGraph?) {
        _activeSketchContext?.setRenderGraph(graph)
    }
}

// MARK: - CoreML / Vision

extension Sketch {
    /// Create a CoreML model processor.
    ///
    /// - Returns: A new ``MLProcessor`` instance.
    public func createMLProcessor() -> MLProcessor {
        activeContext().createMLProcessor()
    }

    /// Create a Vision framework wrapper for image analysis.
    ///
    /// - Returns: A new ``MLVision`` instance.
    public func createVision() -> MLVision {
        activeContext().createVision()
    }

    /// Create a style transfer wrapper for image-to-image models.
    ///
    /// - Returns: A new ``MLStyleTransfer`` instance.
    public func createStyleTransfer() -> MLStyleTransfer {
        activeContext().createStyleTransfer()
    }

    /// Load a CoreML model from a file path.
    ///
    /// - Parameters:
    ///   - path: The file path to the `.mlmodelc` or `.mlpackage` file.
    ///   - computeUnit: The compute unit preference for inference.
    /// - Returns: An ``MLProcessor`` loaded with the model.
    public func loadMLModel(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        try activeContext().loadMLModel(path, computeUnit: computeUnit)
    }

    /// Load a CoreML model from a bundle resource by name.
    ///
    /// - Parameters:
    ///   - name: The resource name of the model.
    ///   - computeUnit: The compute unit preference for inference.
    /// - Returns: An ``MLProcessor`` loaded with the model.
    public func loadMLModel(named name: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        try activeContext().loadMLModel(named: name, computeUnit: computeUnit)
    }

    /// Load a style transfer model from a file path.
    ///
    /// - Parameters:
    ///   - path: The file path to the style transfer model.
    ///   - computeUnit: The compute unit preference for inference.
    /// - Returns: An ``MLStyleTransfer`` loaded with the model.
    public func loadStyleTransfer(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLStyleTransfer {
        try activeContext().loadStyleTransfer(path, computeUnit: computeUnit)
    }

    /// Create a texture converter for Metal-CoreML interoperability (advanced).
    ///
    /// - Returns: A new ``MLTextureConverter`` instance.
    public func createMLTextureConverter() -> MLTextureConverter {
        activeContext().createMLTextureConverter()
    }
}

// MARK: - GameplayKit Noise

extension Sketch {
    /// Create a GameplayKit noise generator.
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - config: The noise generation configuration.
    /// - Returns: A new ``GKNoiseWrapper`` instance.
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper {
        activeContext().createNoise(type, config: config)
    }

    /// Generate a noise texture as an image (convenience method).
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - config: The noise generation configuration.
    /// - Returns: The generated noise image, or `nil` if generation fails.
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        activeContext().noiseTexture(type, width: width, height: height, config: config)
    }
}

// MARK: - MPS

extension Sketch {
    /// Create an MPS (Metal Performance Shaders) image filter.
    ///
    /// - Returns: A new ``MPSImageFilterWrapper`` instance.
    public func createMPSFilter() -> MPSImageFilterWrapper {
        activeContext().createMPSFilter()
    }

    /// Create an MPS ray tracer for GPU-accelerated ray intersection queries.
    ///
    /// - Parameters:
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: A new ``MPSRayTracer`` instance.
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try activeContext().createRayTracer(width: width, height: height)
    }
}

// MARK: - CoreImage Filter

extension Sketch {
    /// Apply a CoreImage filter preset to an image.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - preset: The filter preset to apply.
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        activeContext().ciFilter(image, preset)
    }

    /// Apply a CoreImage filter to an image by name with custom parameters.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - name: The CIFilter name.
    ///   - parameters: The filter parameters.
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        activeContext().ciFilter(image, name: name, parameters: parameters)
    }

    /// Generate an image using a CoreImage generator filter.
    ///
    /// - Parameters:
    ///   - preset: The generator filter preset.
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: The generated image, or `nil` if generation fails.
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        activeContext().ciGenerate(preset, width: width, height: height)
    }
}

// MARK: - @main Entry Point

extension Sketch {
    /// Launch the sketch application (called by the `@main` attribute).
    public static func main() {
        SketchRunner.run(sketchType: Self.self)
    }
}

// MARK: - SketchConfig

/// Configure the sketch window, canvas, and rendering settings.
public struct SketchConfig: Sendable {
    /// The offscreen texture width in pixels.
    public var width: Int

    /// The offscreen texture height in pixels.
    public var height: Int

    /// The window title.
    public var title: String

    /// The target frame rate.
    public var fps: Int

    /// The Syphon server name (`nil` to disable Syphon output).
    public var syphonName: String?

    /// The window size scale factor (window size = texture size * scale).
    public var windowScale: Float

    /// Launch the sketch in full-screen mode.
    public var fullScreen: Bool

    /// Create a new sketch configuration.
    ///
    /// - Parameters:
    ///   - width: The offscreen texture width in pixels.
    ///   - height: The offscreen texture height in pixels.
    ///   - title: The window title.
    ///   - fps: The target frame rate.
    ///   - syphonName: The Syphon server name (`nil` to disable).
    ///   - windowScale: The window size scale factor.
    ///   - fullScreen: Whether to launch in full-screen mode.
    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5,
        fullScreen: Bool = false
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
        self.fullScreen = fullScreen
    }
}
