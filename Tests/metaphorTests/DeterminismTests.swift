import Metal
import Testing

@testable import MetaphorCore

/// 決定論レンダリングの回帰テスト（Issue #70）。
///
/// AI協調ループ（Probe）が「編集→再観測」を信頼するには、レンダリングが
/// 決定論的でなければならない。ここでは noLoop 相当の単一フレーム描画が
/// - 背景色を **1 フレームで** 確定し（2 フレーム待ち不要）、
/// - `frameCount` を 1 に保ち、
/// - 同一入力で同一スナップショットを生む
/// ことを GPU 読み戻しで検証する。
///
/// 設計の根拠は `docs/design/deterministic-rendering.md` / `docs/adr/0002` を参照。
@Suite("Determinism", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct DeterminismTests {

    /// 実スケッチの noLoop 起動経路（`SketchRunner.startWindowedLoop` /
    /// `startHeadlessLoop`）と同じ結線で、`background()` → クリアカラーを駆動する
    /// onDraw を構成する。`renderFrame()` を 1 回呼ぶ = 論理 1 フレーム。
    private func makeContext(
        clear: Color
    ) throws -> (renderer: MetaphorRenderer, context: SketchContext) {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        // SketchRunner と同じ配線: background() がクリアカラーを renderer へ伝える。
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        // SketchRunner.onDraw と同じ: beginFrame → draw → endFrame。
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            canvas.background(clear)
            context.endFrame()
        }
        // ヘッドレス/noLoop 単一フレームと同条件（draw(in:) で再レンダリングしない）。
        renderer.useExternalRenderLoop = true
        return (renderer, context)
    }

    /// オフスクリーンカラーテクスチャの中心ピクセルを読み戻す（BGRA→RGB）。
    private func readbackCenterPixel(
        _ renderer: MetaphorRenderer
    ) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let staging = try #require(renderer.device.makeTexture(descriptor: desc))

        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        let blit = try #require(cb.makeBlitCommandEncoder())
        blit.copy(
            from: renderer.textureManager.colorTexture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: staging,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var px = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(
            &px, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
        )
        let off = ((h / 2) * w + (w / 2)) * 4
        return (r: px[off + 2], g: px[off + 1], b: px[off + 0])
    }

    /// noLoop の核心: **最初の 1 フレーム**で背景色が確定する（2 フレーム待ち不要）。
    /// 以前は 1 フレーム目で clearColorApplied=false のため全画面クワッドで塗り、
    /// 2 フレーム目で loadAction=.clear に切り替えていた。どちらでも 1 フレーム目の
    /// オフスクリーンは正しい背景色を持つ、という不変条件を固定する。
    @Test("単一フレームで背景色が確定する")
    func backgroundDeterministicInOneFrame() throws {
        let (renderer, _) = try makeContext(clear: Color(r: 0, g: 0, b: 1))
        renderer.renderFrame()  // 論理 1 フレームのみ

        let p = try readbackCenterPixel(renderer)
        #expect(p.b > 250, "1 フレーム目で青背景が確定すべき: B=\(p.b)")
        #expect(p.r < 8, "R=\(p.r)")
        #expect(p.g < 8, "G=\(p.g)")
    }

    /// noLoop の単一フレーム化で `frameCount` が 1 になる（旧実装は 2 だった）。
    @Test("noLoop 単一フレームで frameCount は 1")
    func frameCountIsOneAfterSingleFrame() throws {
        let (renderer, context) = try makeContext(clear: Color(r: 0, g: 0, b: 1))
        #expect(context.frameCount == 0)
        renderer.renderFrame()
        #expect(context.frameCount == 1, "1 回の renderFrame は frameCount を 1 にすべき")
    }

    /// 各 `renderFrame()` は `frameCount` をちょうど 1 だけ進める（隠れ二重描画がない）。
    @Test("renderFrame はフレームを正確に1つ進める")
    func renderFrameAdvancesExactlyOne() throws {
        let (renderer, context) = try makeContext(clear: Color(r: 0, g: 0, b: 1))
        renderer.renderFrame()
        renderer.renderFrame()
        #expect(context.frameCount == 2)
    }

    /// 同一スケッチを 2 回レンダリングすると同一ピクセルを生む（snapshot 一致）。
    @Test("同一入力は同一スナップショットを生む")
    func identicalInputProducesIdenticalSnapshot() throws {
        let (r1, _) = try makeContext(clear: Color(r: 0, g: 0, b: 1))
        r1.renderFrame()
        let a = try readbackCenterPixel(r1)

        let (r2, _) = try makeContext(clear: Color(r: 0, g: 0, b: 1))
        r2.renderFrame()
        let b = try readbackCenterPixel(r2)

        #expect(a == b, "同一スケッチの単一フレーム snapshot は一致すべき: \(a) vs \(b)")
    }
}
