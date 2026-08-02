import Metal
import MetaphorCore

/// Defines the interface for nodes within a ``RenderGraph``.
///
/// Each node conforming to ``RenderPassNode`` performs its rendering work in the
/// ``execute(commandBuffer:time:renderer:)`` method and exposes the result through
/// the ``output`` texture property.
///
/// ## Requirements for implementing a custom node
///
/// You must implement **frameToken-based memoization** at the top of `execute`.
/// The built-in nodes (``SourcePass`` / ``EffectPass`` / ``MergePass``) use this
/// pattern so that a node shared in a diamond shape is still executed only once
/// per frame. Without memoization, a shared node would be executed redundantly, and
/// if the graph contains a cycle, infinite recursion would cause a stack overflow.
///
/// ```swift
/// private var lastExecutedToken: UInt64 = .max  // .max = not-yet-executed sentinel
///
/// func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
///     guard lastExecutedToken != renderer.frameToken else { return }
///     lastExecutedToken = renderer.frameToken  // set this before calling execute on inputs
///     // ... execute input passes -> perform this node's own work ...
/// }
/// ```
@MainActor
public protocol RenderPassNode: AnyObject {
    /// A debug label that identifies this node.
    var label: String { get }

    /// The output texture produced after execution. `nil` if not yet executed.
    var output: MTLTexture? { get }

    /// Executes this node's rendering work and produces the ``output`` texture.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode the work into.
    ///   - time: The elapsed time, in seconds.
    ///   - renderer: A reference to the `MetaphorRenderer` that provides shared resources.
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer)
}
