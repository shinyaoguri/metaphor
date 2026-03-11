@preconcurrency import Metal

/// Define the interface for a render graph that can be executed by the renderer.
///
/// This protocol breaks the circular dependency between MetaphorCore and
/// MetaphorRenderGraph. The concrete ``RenderGraph`` class in MetaphorRenderGraph
/// conforms to this protocol, while ``MetaphorRenderer`` only references the protocol.
@MainActor
public protocol RenderGraphExecutable: AnyObject {
    /// Execute the render graph and return the final output texture.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode work into.
    ///   - time: The elapsed time in seconds.
    ///   - renderer: The ``MetaphorRenderer`` reference providing shared resources.
    /// - Returns: The final output texture, or `nil` if execution failed.
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) -> MTLTexture?
}
