import Metal

// MARK: - Plugin Event Types

/// The type of mouse event delivered to a plugin.
public enum MouseEventType: Sendable {
    case pressed
    case released
    case moved
    case dragged
    case scrolled
    case clicked
}

/// The type of keyboard event delivered to a plugin.
public enum KeyEventType: Sendable {
    case pressed
    case released
}

// MARK: - MetaphorPlugin Protocol

/// A plugin that hooks into the metaphor rendering lifecycle.
///
/// Plugins receive callbacks at key points in the frame cycle,
/// enabling features like Syphon output, NDI streaming, or custom
/// recording without modifying the core renderer.
///
/// Register plugins via ``Sketch/registerPlugin(_:)`` or
/// ``SketchConfig/plugins``.
///
/// ```swift
/// final class MyPlugin: MetaphorPlugin {
///     let pluginID = "com.example.myplugin"
///
///     func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
///         // Process the rendered frame
///     }
/// }
/// ```
@MainActor
public protocol MetaphorPlugin: AnyObject {
    /// A unique identifier for this plugin.
    var pluginID: String { get }

    // MARK: - Lifecycle

    /// Called once when the plugin is registered with a sketch.
    ///
    /// The sketch reference provides access to the renderer, input state,
    /// canvas, and all sketch properties (width, height, mouseX, frameCount, etc.).
    /// - Parameter sketch: The sketch this plugin is attached to.
    func onAttach(sketch: any Sketch)

    /// Called once when the plugin is registered with a renderer (legacy).
    ///
    /// Prefer ``onAttach(sketch:)`` for new plugins. This method is called
    /// for backward compatibility when registered via ``MetaphorRenderer/addPlugin(_:)``.
    /// - Parameter renderer: The renderer this plugin is attached to.
    func onAttach(renderer: MetaphorRenderer)

    /// Called once when the plugin is removed from the renderer.
    func onDetach()

    // MARK: - Frame Hooks

    /// Called at the beginning of each frame, before rendering.
    ///
    /// Use this for pre-frame logic such as updating simulation state.
    /// - Parameters:
    ///   - commandBuffer: The command buffer for the current frame.
    ///   - time: The elapsed time in seconds since the sketch started.
    func pre(commandBuffer: MTLCommandBuffer, time: Double)

    /// Called after the frame has been rendered to the offscreen texture.
    ///
    /// Use this for post-frame logic such as capturing or streaming the output.
    /// - Parameters:
    ///   - texture: The final rendered texture (after post-processing).
    ///   - commandBuffer: The command buffer for the current frame.
    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer)

    /// Called when the render loop starts.
    func onStart()

    /// Called when the render loop stops.
    func onStop()

    // MARK: - Input Events

    /// Called when a mouse event occurs.
    ///
    /// - Parameters:
    ///   - x: The mouse x position in sketch coordinates.
    ///   - y: The mouse y position in sketch coordinates.
    ///   - button: The mouse button number (0 = left, 1 = right, 2 = other).
    ///   - type: The type of mouse event.
    func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType)

    /// Called when a keyboard event occurs.
    ///
    /// - Parameters:
    ///   - key: The character that was pressed, or `nil` for non-character keys.
    ///   - keyCode: The virtual key code.
    ///   - type: The type of keyboard event.
    func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType)

    // MARK: - Canvas Events

    /// Called when the canvas is resized.
    /// - Parameters:
    ///   - width: The new width in pixels.
    ///   - height: The new height in pixels.
    func onResize(width: Int, height: Int)

    // MARK: - Legacy (Deprecated)

    /// Called at the beginning of each frame, before rendering.
    @available(*, deprecated, renamed: "pre(commandBuffer:time:)")
    func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double)

    /// Called after the frame has been rendered to the offscreen texture.
    @available(*, deprecated, renamed: "post(texture:commandBuffer:)")
    func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer)
}

// MARK: - Default Implementations

extension MetaphorPlugin {
    public func onAttach(sketch: any Sketch) {}
    public func onAttach(renderer: MetaphorRenderer) {}
    public func onDetach() {}
    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}
    public func onStart() {}
    public func onStop() {}
    public func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {}
    public func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {}
    public func onResize(width: Int, height: Int) {}
    public func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double) {}
    public func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}
}
