import Metal

/// Define the interface for a node in a ``RenderGraph``.
///
/// Each node conforming to ``RenderPassNode`` performs rendering work in its
/// ``execute(commandBuffer:time:renderer:)`` method and exposes the result
/// via the ``output`` texture property.
@MainActor
public protocol RenderPassNode: AnyObject {
    /// The debug label identifying this node.
    var label: String { get }

    /// The output texture produced after execution, or `nil` if not yet executed.
    var output: MTLTexture? { get }

    /// Execute this node's rendering work and populate the ``output`` texture.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode work into.
    ///   - time: The elapsed time in seconds.
    ///   - renderer: The ``MetaphorRenderer`` reference providing shared resources.
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer)
}
