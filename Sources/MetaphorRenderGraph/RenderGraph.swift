import Metal
import MetaphorCore

/// Manages a directed acyclic graph of render passes for multi-pass rendering.
///
/// ``RenderGraph`` executes a tree of ``RenderPassNode`` instances and returns
/// the final output texture. Combine ``SourcePass``, ``EffectPass``, and
/// ``MergePass`` nodes to build complex compositing pipelines.
///
/// ```swift
/// // Draw two scenes, apply bloom to one, then composite them
/// let scene1 = try SourcePass(label: "bg", device: device, width: 1920, height: 1080)
/// let scene2 = try SourcePass(label: "fg", device: device, width: 1920, height: 1080)
/// let bloomed = try EffectPass(
///     scene2, effects: [BloomEffect()],
///     device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
/// )
/// let merged = try MergePass(scene1, bloomed, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// let graph = RenderGraph(root: merged)
///
/// renderer.renderGraph = graph
/// ```
@MainActor
public final class RenderGraph: RenderGraphExecutable {
    /// The graph's root node, which provides the final output texture.
    public let root: RenderPassNode

    /// Creates a new render graph with the given root node.
    ///
    /// - Parameter root: The root node that produces the graph's final output.
    public init(root: RenderPassNode) {
        self.root = root
    }

    /// Executes the entire graph and returns the final output texture.
    ///
    /// Recursively executes all nodes starting from the root, encoding the
    /// rendering work into the provided command buffer.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode the rendering work into.
    ///   - time: The elapsed time, in seconds, passed to each node.
    ///   - renderer: A reference to the ``MetaphorRenderer`` that provides shared resources.
    /// - Returns: The final output texture, or `nil` if execution fails.
    @discardableResult
    public func execute(
        commandBuffer: MTLCommandBuffer,
        time: Double,
        renderer: MetaphorRenderer
    ) -> MTLTexture? {
        root.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        return root.output
    }
}
