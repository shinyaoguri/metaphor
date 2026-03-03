/// Describe how the render loop should be driven.
///
/// The default `.displayLink` mode uses MTKView's built-in display-link
/// for frame pacing. Use `.timer(fps:)` for scenarios that require
/// decoupled frame timing, such as Syphon output or video recording.
public enum RenderLoopMode: Sendable, Equatable {
    /// Use MTKView's built-in display-link driven rendering (default).
    case displayLink

    /// Use a DispatchSourceTimer for independent frame timing.
    ///
    /// This decouples rendering from window refresh and prevents
    /// `currentDrawable` from blocking when the window is occluded.
    /// - Parameter fps: The target frame rate.
    case timer(fps: Int)
}
