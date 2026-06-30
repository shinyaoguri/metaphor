import Metal
import Testing

@testable import MetaphorCore

/// 統一コマンドストリーム基盤の単体テスト（Issue #71 / ADR-0003 PR-1）。
///
/// PR-1 は「即時描画→順序保持コマンド記録」への土台として、呼び出し順を表す
/// 単調シーケンス番号（seq）の払い出しと、2D/3D を seq 昇順で1本へマージする
/// 純粋ユーティリティを導入する。ここではその基盤の正しさを固定する
/// （flush 群への配線は PR-2、interleave 再生への組み込みは PR-3）。
@Suite("CommandStream")
struct CommandStreamTests {

    // MARK: - 呼び出し順マージ（GPU 不要の純粋ロジック）

    @Test("seq 昇順で 2D/3D を呼び出し順にマージする")
    func mergeInterleaved() {
        // 3D が seq 0,2,3 / 2D が seq 1,4 で記録された ＝ box, rect, box, box, rect の順。
        let order = DrawStreamMerge.mergeOrder(threeDSeqs: [0, 2, 3], twoDSeqs: [1, 4])
        #expect(order == [
            .threeD(index: 0),
            .twoD(index: 0),
            .threeD(index: 1),
            .threeD(index: 2),
            .twoD(index: 1),
        ])
    }

    @Test("片方が空でも順序を保つ")
    func mergeEmptyStreams() {
        #expect(DrawStreamMerge.mergeOrder(threeDSeqs: [0, 1, 2], twoDSeqs: []) == [
            .threeD(index: 0), .threeD(index: 1), .threeD(index: 2),
        ])
        #expect(DrawStreamMerge.mergeOrder(threeDSeqs: [], twoDSeqs: [0, 1]) == [
            .twoD(index: 0), .twoD(index: 1),
        ])
        #expect(DrawStreamMerge.mergeOrder(threeDSeqs: [], twoDSeqs: []).isEmpty)
    }

    @Test("2D 背景 → 3D → 2D 前景 の順序が保持される")
    func mergeBackgroundThenForeground() {
        // 2D 背景(seq0) → 3D(seq1,2) → 2D 前景(seq3) のパターン（宿題①の支配ケース）。
        let order = DrawStreamMerge.mergeOrder(threeDSeqs: [1, 2], twoDSeqs: [0, 3])
        #expect(order == [
            .twoD(index: 0),     // 背景
            .threeD(index: 0),
            .threeD(index: 1),
            .twoD(index: 1),     // 前景
        ])
    }

    @Test("Deferred2DCommand と slot を seq 付きで構築できる")
    func deferred2DCommandConstruction() {
        let slots = [
            Deferred2DSlot(seq: 0, command: .setScissor(nil)),
            Deferred2DSlot(seq: 1, command: .colorBatch(blend: .alpha, vertexStart: 0, vertexCount: 6)),
        ]
        #expect(slots.map(\.seq) == [0, 1])
        if case .colorBatch(let blend, _, let count) = slots[1].command {
            #expect(blend == .alpha)
            #expect(count == 6)
        } else {
            Issue.record("colorBatch を期待")
        }
    }
}

/// seq 払い出し基盤を実コンテキスト経由で検証する（GPU 必須）。
@Suite("CommandStream/Seq", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CommandStreamSeqTests {

    private func makeContext() throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        return (renderer, context)
    }

    @Test("nextDrawSeq は単調増加し beginFrame でリセットされる")
    func seqMonotonicAndResetsPerFrame() throws {
        let (_, context) = try makeContext()
        #expect(context.nextDrawSeq() == 0)
        #expect(context.nextDrawSeq() == 1)
        #expect(context.nextDrawSeq() == 2)

        context.beginFrame(encoder: nil, time: 0, deltaTime: 0)
        #expect(context.nextDrawSeq() == 0, "beginFrame で seq カウンタは 0 にリセットされるべき")
        #expect(context.nextDrawSeq() == 1)
    }

    /// 影オン経路（記録→shadow→再生）を実スケッチと同じ結線で構成する。
    private func makeShadowHarness(
        width: Int = 64, height: Int = 64,
        draw: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: width, height: height)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.onAfterDraw = { cb in context.canvas3D.performShadowPass(commandBuffer: cb) }
        renderer.shadowDeferActive = { context.canvas3D.defersMainPassForShadow }
        renderer.onRecordFrame = { time in
            context.beginRecordingFrame(time: Float(time), deltaTime: 0)
            draw(context)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, time in
            context.replayDeferredMain(encoder: encoder, time: Float(time))
        }
        renderer.useExternalRenderLoop = true
        return (renderer, context)
    }

    /// オフスクリーンカラーテクスチャ全体を読み戻し、任意座標をサンプルできるようにする
    /// （重ね順・clip は中心1点では検出力不足のため複数サンプル点で検証する）。
    private func readbackPixels(
        _ renderer: MetaphorRenderer
    ) throws -> (w: Int, h: Int, sample: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) {
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
        staging.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return (w, h, { x, y in
            let off = (y * w + x) * 4
            return (r: px[off + 2], g: px[off + 1], b: px[off + 0])
        })
    }

    /// 宿題②: massive 2D（`circles`）が影オン記録経路でも描画される
    /// （#70 では encoder 必須ガードで黙ってスキップされていた）。
    @Test("影オン記録経路で massive circles が描画される")
    func massiveCirclesDrawnInShadowPath() throws {
        let (renderer, context) = try makeShadowHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))   // 黒背景
            c.lights()
            c.fill(Color(r: 0, g: 1, b: 0))          // hasFill を有効化（massive 色は instance 側）
            c.circles([CircleInstance(x: 32, y: 32, diameter: 56, color: Color(r: 0, g: 1, b: 0))])
        }
        context.enableShadows()
        renderer.renderFrame()

        let (_, _, sample) = try readbackPixels(renderer)
        let p = sample(32, 32)
        #expect(p.g > 200 && p.r < 60 && p.b < 60, "中心は緑の円で塗られるべき: \(p)")
    }

    /// 宿題③: 2D クリップ（scissor）が影オン記録経路でも効く
    /// （#70 では遅延クロージャに scissor が乗らず前景再生で失われていた）。
    @Test("影オン記録経路で 2D クリップが効く")
    func clipRespectedInShadowPath() throws {
        let (renderer, context) = try makeShadowHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))   // 黒背景
            c.lights()
            c.beginClip(0, 0, 32, 32)                // 左上 1/4 にクリップ
            c.fill(Color(r: 1, g: 0, b: 0))
            c.noStroke()
            c.rect(0, 0, 64, 64)                     // フルスクリーン矩形（クリップで左上のみ）
            c.endClip()
        }
        context.enableShadows()
        renderer.renderFrame()

        let (_, _, sample) = try readbackPixels(renderer)
        let inside = sample(16, 16)
        let outside = sample(48, 48)
        #expect(inside.r > 200 && inside.g < 60, "クリップ内は赤であるべき: \(inside)")
        #expect(outside.r < 60 && outside.g < 60 && outside.b < 60,
                "クリップ外は黒のままであるべき（clip が効いている）: \(outside)")
    }

    @Test("影オン記録経路で 3D ドローコールが呼び出し順の seq を持つ")
    func recordedDrawCallsCarryCallOrderSeq() throws {
        let (renderer, context) = try makeContext()
        let w: Float = 32
        renderer.onRecordFrame = { time in
            context.beginRecordingFrame(time: Float(time), deltaTime: 0)
            context.background(Color(r: 0, g: 0, b: 1))   // 2D: PR-1 では seq を消費しない
            context.lights()
            context.fill(Color(r: 1, g: 1, b: 1))
            context.box(w / 4)                             // 3D #0
            context.box(w / 4)                             // 3D #1
            context.box(w / 4)                             // 3D #2
            context.endRecordingFrame()
        }
        renderer.onAfterDraw = { cb in context.canvas3D.performShadowPass(commandBuffer: cb) }
        renderer.shadowDeferActive = { context.canvas3D.defersMainPassForShadow }
        renderer.onReplayMain = { encoder, time in
            context.replayDeferredMain(encoder: encoder, time: Float(time))
        }
        renderer.useExternalRenderLoop = true

        context.enableShadows()
        renderer.renderFrame()

        let seqs = context.canvas3D.recordedDrawCalls.map(\.seq)
        #expect(seqs == [0, 1, 2], "3 つの box は呼び出し順に seq 0,1,2 を持つべき: \(seqs)")
    }
}
