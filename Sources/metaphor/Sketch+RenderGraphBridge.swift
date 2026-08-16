import MetaphorCore
import MetaphorRenderGraph

// MARK: - レンダーグラフブリッジ

extension Sketch {
    /// レンダーグラフ用のソースパスを作成します。
    ///
    /// - Parameters:
    ///   - label: パスのデバッグラベル。
    ///   - width: レンダーターゲットの幅（ピクセル単位）。
    ///   - height: レンダーターゲットの高さ（ピクセル単位）。
    /// - Returns: 新しい ``MetaphorRenderGraph/SourcePass`` インスタンス。作成に失敗した場合は `nil`。
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        guard width > 0, height > 0 else {
            metaphorWarning("createSourcePass: dimensions must be positive (got \(width)x\(height))")
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

    /// レンダーパスにポストプロセスエフェクトを適用するエフェクトパスを作成します。
    ///
    /// - Parameters:
    ///   - input: 入力レンダーパスノード。
    ///   - effects: 適用するポストプロセスエフェクト。
    /// - Returns: 新しい ``MetaphorRenderGraph/EffectPass`` インスタンス。作成に失敗した場合は `nil`。
    public func createEffectPass(_ input: RenderPassNode, effects: [any PostEffect]) -> EffectPass? {
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

    /// 2つのレンダーパスを合成するマージパスを作成します。
    ///
    /// - Parameters:
    ///   - a: 1つ目の入力レンダーパスノード。
    ///   - b: 2つ目の入力レンダーパスノード。
    ///   - blend: 合成用のブレンドタイプ。
    /// - Returns: 新しい ``MetaphorRenderGraph/MergePass`` インスタンス。作成に失敗した場合は `nil`。
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
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

    /// アクティブなレンダーグラフを設定またはクリアします。
    ///
    /// `nil` を渡すと現在のレンダーグラフが**クリア**され、以降のフレームは
    /// レンダーグラフを経由しない通常の描画パスに戻ります（別途 `clearRenderGraph()`
    /// のような削除用 API は用意していません）。
    ///
    /// - Parameter graph: 使用するレンダーグラフ。無効化（クリア）するには `nil`。
    public func setRenderGraph(_ graph: RenderGraph?) {
        context.renderer.renderGraph = graph
    }
}
