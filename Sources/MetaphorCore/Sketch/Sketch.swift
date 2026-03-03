#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@preconcurrency import Metal
import ObjectiveC

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

// MARK: - Per-Instance Context (Associated Object)

// Address used as the key for objc_getAssociatedObject/objc_setAssociatedObject.
// The value is never mutated at runtime; only its pointer is used.
private nonisolated(unsafe) var sketchContextKey: UInt8 = 0

extension Sketch {
    /// The sketch context associated with this instance.
    /// Set by SketchRunner during setup.
    @MainActor
    internal var _context: SketchContext? {
        get { objc_getAssociatedObject(self, &sketchContextKey) as? SketchContext }
        set { objc_setAssociatedObject(self, &sketchContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Retrieve the active context, raising a fatal error if called outside `setup()` or `draw()`.
    @MainActor
    internal func activeContext(function: String = #function) -> SketchContext {
        guard let ctx = _context else {
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

    /// The render loop mode.
    ///
    /// Use `.displayLink` (default) for standard rendering driven by the display
    /// refresh rate. Use `.timer(fps:)` for decoupled frame timing, which is
    /// useful for Syphon output or video recording where rendering should not
    /// stall when the window is occluded.
    public var renderLoopMode: RenderLoopMode

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
    ///   - renderLoopMode: The render loop mode (default: `.displayLink`).
    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5,
        fullScreen: Bool = false,
        renderLoopMode: RenderLoopMode = .displayLink
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
        self.fullScreen = fullScreen
        self.renderLoopMode = renderLoopMode
    }
}
