import AppKit
@preconcurrency import Metal

/// Define a sketch by conforming to this protocol.
///
/// Annotate your class with `@main` and implement `draw()` to receive
/// automatic window, renderer, and Canvas2D setup. The `draw()` method
/// is called every frame.
///
/// ```swift
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

    /// Draw a single frame (call drawing methods directly).
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

    /// Respond to a mouse click (press and release without dragging).
    func mouseClicked()

    /// Respond to a key press.
    func keyPressed()

    /// Respond to a key release.
    func keyReleased()
}

// MARK: - Per-Instance Context (Pure Swift Storage)

/// Storage for Sketch → SketchContext mapping (replaces objc_getAssociatedObject).
@MainActor
private var _sketchContextStorage: [ObjectIdentifier: SketchContext] = [:]

extension Sketch {
    /// The sketch context associated with this instance.
    /// Set by SketchRunner during setup.
    @MainActor
    internal var _context: SketchContext? {
        get { _sketchContextStorage[ObjectIdentifier(self)] }
        set {
            if let newValue {
                _sketchContextStorage[ObjectIdentifier(self)] = newValue
            } else {
                _sketchContextStorage.removeValue(forKey: ObjectIdentifier(self))
            }
        }
    }

    /// The active context. Crashes with a clear message if called outside setup()/draw().
    @MainActor
    public var context: SketchContext {
        guard let ctx = _context else {
            fatalError("[metaphor] Drawing methods cannot be called outside setup()/draw(). Ensure SketchRunner has initialized the context.")
        }
        return ctx
    }
}

// MARK: - Default Implementations

extension Sketch {
    public var config: SketchConfig { SketchConfig() }
    public func setup() {}
    public func draw() {}
    public func compute() {}
    public func mousePressed() {}
    public func mouseReleased() {}
    public func mouseMoved() {}
    public func mouseDragged() {}
    public func mouseScrolled() {}
    public func mouseClicked() {}
    public func keyPressed() {}
    public func keyReleased() {}
}

// MARK: - Deprecated

extension Sketch {
    /// Draw a single frame using an explicit context parameter.
    ///
    /// - Parameter ctx: The sketch context.
    @available(*, deprecated, message: "Use draw() instead. Access context via self properties or self._context.")
    public func draw(_ ctx: SketchContext) { draw() }
}

// MARK: - @main Entry Point

extension Sketch {
    /// Launch the sketch application (called by the `@main` attribute).
    public static func main() {
        SketchRunner.run(sketchType: Self.self)
    }
}

// MARK: - PluginFactory

/// A factory that creates a plugin instance for use in ``SketchConfig``.
///
/// Because ``SketchConfig`` is `Sendable` and plugins are reference types,
/// plugin creation is deferred via a factory closure.
///
/// ```swift
/// var config: SketchConfig {
///     SketchConfig(
///         title: "My Sketch",
///         plugins: [
///             PluginFactory { MyPlugin() },
///             PluginFactory { NDIOutput(port: 5960) },
///         ]
///     )
/// }
/// ```
public struct PluginFactory: @unchecked Sendable {
    private let _create: @MainActor () -> MetaphorPlugin

    /// Create a factory from a closure that produces a plugin.
    /// - Parameter create: A closure that returns a new plugin instance.
    public init(_ create: @MainActor @escaping () -> MetaphorPlugin) {
        self._create = create
    }

    /// Instantiate the plugin.
    @MainActor
    public func create() -> MetaphorPlugin {
        _create()
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

    /// Plugin factories to register during sketch setup.
    ///
    /// Plugins are instantiated and attached to the sketch before ``Sketch/setup()`` is called.
    /// ```swift
    /// var config: SketchConfig {
    ///     SketchConfig(plugins: [PluginFactory { MyPlugin() }])
    /// }
    /// ```
    public var plugins: [PluginFactory]

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
    ///   - plugins: An array of plugin factories to register with the sketch.
    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5,
        fullScreen: Bool = false,
        renderLoopMode: RenderLoopMode = .displayLink,
        plugins: [PluginFactory] = []
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
        self.fullScreen = fullScreen
        self.renderLoopMode = renderLoopMode
        self.plugins = plugins
    }
}
