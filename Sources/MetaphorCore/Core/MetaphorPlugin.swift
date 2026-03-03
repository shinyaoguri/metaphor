import Metal

/// A plugin that hooks into the metaphor rendering lifecycle.
///
/// Plugins receive callbacks at key points in the frame cycle,
/// enabling features like Syphon output, NDI streaming, or custom
/// recording without modifying the core renderer.
///
/// Register plugins via ``MetaphorRenderer/addPlugin(_:)`` or
/// ``SketchConfig/plugins``.
///
/// ```swift
/// final class MyPlugin: MetaphorPlugin {
///     let pluginID = "com.example.myplugin"
///
///     func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
///         // Process the rendered frame
///     }
/// }
/// ```
@MainActor
public protocol MetaphorPlugin: AnyObject {
    /// A unique identifier for this plugin.
    var pluginID: String { get }

    /// Called once when the plugin is registered with a renderer.
    /// - Parameter renderer: The renderer this plugin is attached to.
    func onAttach(renderer: MetaphorRenderer)

    /// Called once when the plugin is removed from the renderer.
    func onDetach()

    /// Called at the beginning of each frame, before rendering.
    /// - Parameters:
    ///   - commandBuffer: The command buffer for the current frame.
    ///   - time: The elapsed time in seconds since the sketch started.
    func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double)

    /// Called after the frame has been rendered to the offscreen texture.
    /// - Parameters:
    ///   - texture: The final rendered texture (after post-processing).
    ///   - commandBuffer: The command buffer for the current frame.
    func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer)

    /// Called when the render loop starts.
    func onStart()

    /// Called when the render loop stops.
    func onStop()

    /// Called when the canvas is resized.
    /// - Parameters:
    ///   - width: The new width in pixels.
    ///   - height: The new height in pixels.
    func onResize(width: Int, height: Int)
}

// MARK: - Default Implementations

extension MetaphorPlugin {
    public func onAttach(renderer: MetaphorRenderer) {}
    public func onDetach() {}
    public func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}
    public func onStart() {}
    public func onStop() {}
    public func onResize(width: Int, height: Int) {}
}
