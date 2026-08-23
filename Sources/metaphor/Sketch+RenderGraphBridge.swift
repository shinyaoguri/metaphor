import MetaphorCore
import MetaphorRenderGraph

// MARK: - レンダーグラフブリッジ

extension Sketch {
    /// Creates a source pass for a render graph.
    ///
    /// - Parameters:
    ///   - label: A debug label for the pass.
    ///   - width: The render target width, in pixels.
    ///   - height: The render target height, in pixels.
    /// - Returns: A new ``MetaphorRenderGraph/SourcePass`` instance, or `nil` if creation fails.
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        guard width > 0, height > 0 else {
            metaphorWarning(
                "createSourcePass: dimensions must be positive (got \(width)x\(height))")
            return nil
        }
        do {
            return try SourcePass(
                label: label,
                device: context.renderer.device,
                width: width,
                height: height
            )
        } catch {
            metaphorWarning("Failed to create SourcePass '\(label)': \(error)")
            return nil
        }
    }

    /// Creates an effect pass that applies post-processing effects to a render pass.
    ///
    /// - Parameters:
    ///   - input: The input render pass node.
    ///   - effects: The post-processing effects to apply.
    /// - Returns: A new ``MetaphorRenderGraph/EffectPass`` instance, or `nil` if creation fails.
    public func createEffectPass(_ input: RenderPassNode, effects: [any PostEffect]) -> EffectPass?
    {
        guard !effects.isEmpty else {
            metaphorWarning("createEffectPass: effects must not be empty")
            return nil
        }
        do {
            return try EffectPass(
                input,
                effects: effects,
                device: context.renderer.device,
                commandQueue: context.renderer.commandQueue,
                shaderLibrary: context.renderer.shaderLibrary
            )
        } catch {
            metaphorWarning("Failed to create EffectPass: \(error)")
            return nil
        }
    }

    /// Creates a merge pass that composites two render passes.
    ///
    /// - Parameters:
    ///   - a: The first input render pass node.
    ///   - b: The second input render pass node.
    ///   - blend: The blend type used for compositing.
    /// - Returns: A new ``MetaphorRenderGraph/MergePass`` instance, or `nil` if creation fails.
    public func createMergePass(
        _ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType
    ) -> MergePass? {
        do {
            return try MergePass(
                a, b,
                blend: blend,
                device: context.renderer.device,
                shaderLibrary: context.renderer.shaderLibrary
            )
        } catch {
            metaphorWarning("Failed to create MergePass: \(error)")
            return nil
        }
    }

    /// Sets or clears the active render graph.
    ///
    /// Passing `nil` **clears** the current render graph, and later frames go back
    /// to the ordinary render pass without a graph. There is no separate removal
    /// API such as `clearRenderGraph()`.
    ///
    /// - Parameter graph: The render graph to use, or `nil` to clear it.
    public func setRenderGraph(_ graph: RenderGraph?) {
        context.renderer.renderGraph = graph
    }
}
