import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// メインパスをどの経路で処理するか（`Canvas3D.shouldRecordMainPass` の 3 通りの入り方）。
///
/// `MetaphorRenderer.renderFrame()` は `shadowDeferActive` が true のとき
/// 「記録 → shadow → 再生」経路へ分岐する。その分岐を立てる要因は 2 つあり
/// （影オン = `shadowMap != nil` / コマンド記録 opt-in = `commandRecordEnabled`）、
/// 立てない既定が即時経路になる。テスト側からはこの 3 つを区別して選びたいので、
/// `Bool` ではなく列挙で表す。
enum MainPassMode {
    /// 既定。`draw()` がメインエンコーダーへ直接エンコードする即時経路。
    case immediate
    /// 影オン（同一フレームシャドウ、#70 / ADR-0002 フェーズ 3）。記録経路を通る。
    case shadows
    /// 影オフのままコマンド記録経路へ入る opt-in（#71。実行時は `METAPHOR_COMMAND_RECORD=1`）。
    case commandRecord
}

/// `SketchRunner` と同じ結線でオフスクリーンに描き、フレームバッファ全体を読み戻す
/// テスト用ハーネス。
///
/// `SketchRunner.configureRenderCallbacks(...)` は `private` かつ
/// `SketchRunner.run(sketchType:)` が `NSApplication.shared.run()` でブロックするため、
/// テストからランナー本体を駆動できない（#357）。そのためここに**同じ結線を複製**して
/// いる。ランナー側の配線を変えたらここも揃えること。
///
/// 各テストスイートがそれぞれ複製を持っていた状態（`GoldenImageTests` /
/// `CommandRecordParityTests` / `CommandStreamTests` …）を、少なくとも
/// 「フレームバッファ全体を読み戻す」系についてはここ 1 箇所へ寄せる（#375）。
///
/// - Note: 時間依存を排除するため `time` / `deltaTime` は常に 0 を渡す。
///   決定論レンダリング（ADR-0002）の前提であり、ゴールデンもパリティもこれに乗る。
@MainActor
enum OffscreenSketchHarness {

    /// オフスクリーンで `frames` 枚描き、**最後のフレーム**のカラーテクスチャを読み戻す。
    ///
    /// - Parameters:
    ///   - size: 正方形の一辺（ピクセル）。
    ///   - mode: メインパスの経路（``MainPassMode``）。
    ///   - frames: 描画するフレーム数。1 なら初回フレーム、2 以上なら定常フレームを見る。
    ///   - effects: 空でなければ、描画後のカラーテクスチャへポストプロセスを適用した結果を返す。
    ///   - draw: 1 フレームぶんの描画。`SketchRunner` が `sketch.draw()` を呼ぶ位置に入る。
    static func render(
        size: Int,
        mode: MainPassMode = .immediate,
        frames: Int = 1,
        effects: [any PostEffect] = [],
        draw: @escaping (SketchContext) -> Void
    ) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: size, height: size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        // ここから下は SketchRunner.configureRenderCallbacks と同じ結線
        // （compute フェーズだけは描画結果に関与しないので省く）。
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.onAfterDraw = { commandBuffer in
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
        renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
        renderer.onRecordFrame = { _ in
            context.beginRecordingFrame(time: 0, deltaTime: 0)
            draw(context)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, _ in
            context.replayDeferredMain(encoder: encoder, time: 0)
        }
        renderer.useExternalRenderLoop = true

        switch mode {
        case .immediate:
            break
        case .shadows:
            context.enableShadows(resolution: 512)
        case .commandRecord:
            // SketchRunner が METAPHOR_COMMAND_RECORD=1 で立てるフラグと同じもの。
            context.canvas3D.commandRecordEnabled = true
        }

        for _ in 0..<max(1, frames) {
            renderer.renderFrame()
        }

        var output: MTLTexture = renderer.textureManager.colorTexture
        if !effects.isEmpty {
            // renderer.setPostEffects() 経由だと結果が private な lastOutputTexture に
            // 入って読めないため、パイプラインを直接駆動して出力テクスチャを受け取る。
            let pipeline = try #require(renderer.postProcessPipeline)
            pipeline.set(effects)
            let cb = try #require(renderer.commandQueue.makeCommandBuffer())
            output = pipeline.apply(source: output, commandBuffer: cb)
            try MetalTestHelper.commit(cb)
        }
        return try GoldenImage.readback(texture: output, commandQueue: renderer.commandQueue)
    }
}
