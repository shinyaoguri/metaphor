/// Configuration for a secondary sketch window.
///
/// Used with ``SketchWindow`` to define the render resolution, window title,
/// frame rate, and optional Syphon output for a secondary window.
///
/// ```swift
/// let config = SketchWindowConfig(
///     width: 400,
///     height: 300,
///     title: "Preview"
/// )
/// let window = createWindow(config)
/// ```
public struct SketchWindowConfig: Sendable {
    /// The offscreen render texture width in pixels.
    public var width: Int

    /// The offscreen render texture height in pixels.
    public var height: Int

    /// The window title.
    public var title: String

    /// The target frame rate.
    public var fps: Int

    /// The window scale factor (window size = texture size * scale).
    public var windowScale: Float

    /// The Syphon server name, or `nil` to disable Syphon output.
    public var syphonName: String?

    /// The render loop mode.
    ///
    /// Defaults to ``RenderLoopMode/displayLink``. When ``syphonName`` is set
    /// and this remains `.displayLink`, the window automatically switches to
    /// ``RenderLoopMode/timer(fps:)`` for reliable Syphon output.
    public var renderLoopMode: RenderLoopMode = .displayLink

    /// Create a new secondary window configuration.
    ///
    /// - Parameters:
    ///   - width: The offscreen render texture width in pixels.
    ///   - height: The offscreen render texture height in pixels.
    ///   - title: The window title.
    ///   - fps: The target frame rate.
    ///   - windowScale: The window scale factor.
    ///   - syphonName: The Syphon server name, or `nil` to disable.
    ///   - renderLoopMode: The render loop mode (default: `.displayLink`).
    public init(
        width: Int = 800,
        height: Int = 600,
        title: String = "metaphor",
        fps: Int = 60,
        windowScale: Float = 1.0,
        syphonName: String? = nil,
        renderLoopMode: RenderLoopMode = .displayLink
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.windowScale = windowScale
        self.syphonName = syphonName
        self.renderLoopMode = renderLoopMode
    }
}
