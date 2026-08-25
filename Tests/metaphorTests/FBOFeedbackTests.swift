import Testing
import Metal
@testable import MetaphorCore

// MARK: - C-14: FBO Feedback

@Suite("C-14 FBO Feedback", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct FBOFeedbackTests {

    @Test("feedbackEnabled defaults to false")
    func defaultDisabled() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.feedbackEnabled == false)
        #expect(renderer.previousFrameTexture == nil)
    }

    @Test("enableFeedback sets flag")
    func enableDisable() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        ctx.enableFeedback()
        #expect(renderer.feedbackEnabled == true)
        ctx.disableFeedback()
        #expect(renderer.feedbackEnabled == false)
    }

    @Test("previousFrame returns nil when feedback disabled")
    func previousFrameNilWhenDisabled() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let img = ctx.previousFrame()
        #expect(img == nil)
    }

    @Test("previousFrameTexture is nil before any render")
    func previousFrameTextureNilInitially() throws {
        let renderer = try MetaphorRenderer()
        renderer.feedbackEnabled = true
        // renderFrame() を呼ばない状態では nil
        #expect(renderer.previousFrameTexture == nil)
    }

    // MARK: - previousFrame() の loadPixels 順序保証（#479）

    /// フィードバック有効でオフスクリーンフレームを回すハーネス（GoldenImageTests と同型の結線）。
    ///
    /// `draw` は `renderFrame()` のたびに呼ばれる。前フレームのコピー
    /// （`capturePreviousFrame`）はフレーム冒頭・描画前に同じコマンドバッファへ載る。
    private func makeFeedbackHarness(
        size: Int = 64,
        draw: @escaping (SketchContext) -> Void
    ) throws -> (renderer: MetaphorRenderer, context: SketchContext) {
        let renderer = try MetaphorRenderer(width: size, height: size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.useExternalRenderLoop = true
        context.enableFeedback()
        return (renderer, context)
    }

    @Test("previousFrame carries the renderer queue as the readback queue")
    func previousFrameCarriesReadbackQueue() throws {
        let harness = try makeFeedbackHarness { c in
            c.background(Color(r: 1, g: 0, b: 0, alpha: 1))
        }
        harness.renderer.renderFrame()

        let img = try #require(harness.context.previousFrame())
        // リードバックが別キューだと commit 順序が保証されず、loadPixels()/get() が
        // 「そのフレーム冒頭のコピー完了前」の内容を読み得る（#479。3D の同型欠陥が #353）。
        #expect(
            img.preferredReadbackQueue === harness.renderer.commandQueue,
            "previousFrame() は描画キューをリードバックキューとして引き継ぐ")
    }

    @Test("previousFrame loadPixels reads the frame copied at this frame's start")
    func previousFrameLoadPixelsFreshness() throws {
        var color = Color(r: 1, g: 0, b: 0, alpha: 1)
        let harness = try makeFeedbackHarness { c in c.background(color) }

        // フレーム 1: 赤を描く（コピー元はまだ初期状態）
        harness.renderer.renderFrame()
        // フレーム 2: 冒頭で「赤」がコピーされ、そのあと緑を描く
        color = Color(r: 0, g: 1, b: 0, alpha: 1)
        harness.renderer.renderFrame()

        let img = try #require(harness.context.previousFrame())
        img.loadPixels()
        let afterSecond = img.get(Int(img.width) / 2, Int(img.height) / 2)
        #expect(
            afterSecond.r > 0.9 && afterSecond.g < 0.1,
            "フレーム 2 冒頭でコピーされた前フレーム（赤）が読める (got \(afterSecond))")

        // フレーム 3: 冒頭で「緑」がコピーされる → 同じ MImage から最新が読める
        harness.renderer.renderFrame()
        img.loadPixels()
        let afterThird = img.get(Int(img.width) / 2, Int(img.height) / 2)
        #expect(
            afterThird.g > 0.9 && afterThird.r < 0.1,
            "再コピー後の loadPixels が古いキャッシュを返さない (got \(afterThird))")
    }
}
