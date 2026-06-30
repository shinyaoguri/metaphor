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
