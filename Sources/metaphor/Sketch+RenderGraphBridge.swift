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
        do {
            return try SourcePass(
                label: label,
                device: context.renderer.device,
                width: width,
                height: height
            )
        } catch {
            print("[metaphor] Warning: Failed to create SourcePass '\(label)': \(error)")
            return nil
        }
    }

    /// ``createSourcePass(label:width:height:)`` の検証付きバリアント。
    ///
    /// 寸法が不正な場合は ``MetaphorCore/MetaphorError/invalidParameter(_:)`` を、
    /// 生成に失敗した場合はその下層エラーをスローします（nil を返さず原因が分かる）。
    ///
    /// - Parameters:
    ///   - label: パスのデバッグラベル。
    ///   - width: レンダーターゲットの幅（ピクセル、正の値）。
    ///   - height: レンダーターゲットの高さ（ピクセル、正の値）。
    /// - Returns: 新しい ``MetaphorRenderGraph/SourcePass`` インスタンス。
    public func makeSourcePass(label: String, width: Int, height: Int) throws -> SourcePass {
        guard width > 0, height > 0 else {
            throw MetaphorError.invalidParameter("SourcePass の寸法は正である必要があります (指定: \(width)x\(height))")
        }
        return try SourcePass(
            label: label,
            device: context.renderer.device,
            width: width,
            height: height
        )
    }

    /// レンダーパスにポストプロセスエフェクトを適用するエフェクトパスを作成します。
    ///
    /// - Parameters:
    ///   - input: 入力レンダーパスノード。
    ///   - effects: 適用するポストプロセスエフェクト。
    /// - Returns: 新しい ``MetaphorRenderGraph/EffectPass`` インスタンス。作成に失敗した場合は `nil`。
    public func createEffectPass(_ input: RenderPassNode, effects: [any PostEffect]) -> EffectPass? {
        do {
            return try EffectPass(
                input,
                effects: effects,
                device: context.renderer.device,
                commandQueue: context.renderer.commandQueue,
                shaderLibrary: context.renderer.shaderLibrary
            )
        } catch {
            print("[metaphor] Warning: Failed to create EffectPass: \(error)")
            return nil
        }
    }

    /// ``createEffectPass(_:effects:)`` の検証付きバリアント。
    ///
    /// `effects` が空の場合は ``MetaphorCore/MetaphorError/invalidParameter(_:)`` を、
    /// 生成に失敗した場合はその下層エラーをスローします（nil を返さず原因が分かる）。
    ///
    /// - Parameters:
    ///   - input: 入力レンダーパスノード。
    ///   - effects: 適用するポストプロセスエフェクト（1 つ以上）。
    /// - Returns: 新しい ``MetaphorRenderGraph/EffectPass`` インスタンス。
    public func makeEffectPass(_ input: RenderPassNode, effects: [any PostEffect]) throws -> EffectPass {
        guard !effects.isEmpty else {
            throw MetaphorError.invalidParameter("EffectPass には 1 つ以上のエフェクトが必要です")
        }
        return try EffectPass(
            input,
            effects: effects,
            device: context.renderer.device,
            commandQueue: context.renderer.commandQueue,
            shaderLibrary: context.renderer.shaderLibrary
        )
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
            print("[metaphor] Warning: Failed to create MergePass: \(error)")
            return nil
        }
    }

    /// アクティブなレンダーグラフを設定またはクリアします。
    ///
    /// - Parameter graph: 使用するレンダーグラフ。無効にするには `nil`。
    public func setRenderGraph(_ graph: RenderGraph?) {
        context.renderer.renderGraph = graph
    }
}
