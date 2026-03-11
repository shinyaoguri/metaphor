import MetaphorCore
import MetaphorRenderGraph

// MARK: - Render Graph Bridge

extension Sketch {
    /// Create a source pass for the render graph.
    ///
    /// - Parameters:
    ///   - label: The debug label for the pass.
    ///   - width: The render target width in pixels.
    ///   - height: The render target height in pixels.
    /// - Returns: A new ``SourcePass`` instance, or `nil` if creation fails.
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        try? SourcePass(
            label: label,
            device: context.renderer.device,
            width: width,
            height: height
        )
    }

    /// Create an effect pass that applies post-processing effects to a render pass.
    ///
    /// - Parameters:
    ///   - input: The input render pass node.
    ///   - effects: The post-processing effects to apply.
    /// - Returns: A new ``EffectPass`` instance, or `nil` if creation fails.
    public func createEffectPass(_ input: RenderPassNode, effects: [any PostEffect]) -> EffectPass? {
        try? EffectPass(
            input,
            effects: effects,
            device: context.renderer.device,
            commandQueue: context.renderer.commandQueue,
            shaderLibrary: context.renderer.shaderLibrary
        )
    }

    /// Create a merge pass that combines two render passes.
    ///
    /// - Parameters:
    ///   - a: The first input render pass node.
    ///   - b: The second input render pass node.
    ///   - blend: The blend type for compositing.
    /// - Returns: A new ``MergePass`` instance, or `nil` if creation fails.
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        try? MergePass(
            a, b,
            blend: blend,
            device: context.renderer.device,
            shaderLibrary: context.renderer.shaderLibrary
        )
    }

    /// Set or clear the active render graph.
    ///
    /// - Parameter graph: The render graph to use, or `nil` to disable.
    public func setRenderGraph(_ graph: RenderGraph?) {
        context.renderer.renderGraph = graph
    }
}
