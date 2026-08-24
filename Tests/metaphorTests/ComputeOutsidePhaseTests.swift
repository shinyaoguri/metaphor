import Testing
import Metal

@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

/// `compute()` の外から GPU 作業を頼まれたときに、無言で捨てずに声を出す (Issue #1092)。
///
/// `createComputeKernel` と `createBuffer` は `setup()` でも正しく動くため、GPU まわりの
/// 初期化を `setup()` にまとめるのは自然な書き方になる。ところが `dispatch` だけは
/// コンピュートフェーズ (`beginCompute` / `endCompute` の間) にしかエンコードできず、
/// 修正前はそこが `guard let cb = _commandBuffer else { return nil }` の無言終了だった。
/// 「エラーも警告も出ないのに何も起きない」が一番気付きにくい失敗の形なので、
/// ここでは**何も起きないこと自体は変えず、必ず 1 行残ること**を守る。
@Suite("compute() の外からの GPU 作業", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ComputeOutsidePhaseTests {

    /// 走れば必ずバッファへ 42 を書くカーネル。「動かなかった」ことを値で判定するために使う。
    private static let fillSource = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void fill(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 42.0;
        }
        """

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    // MARK: - 外から呼んだとき

    @Test("compute() の外の dispatch は何も起きないが、警告は残る")
    func dispatchOutsideComputeWarns() throws {
        let context = try makeContext()
        let kernel = try context.createComputeKernel(source: Self.fillSource, function: "fill")
        let buffer = try #require(context.createBuffer(count: 16, type: Float.self))
        buffer[0] = -1

        // `setup()` / `draw()` から呼ぶのと同じ状態 (コマンドバッファが無い)。
        context.dispatch(kernel, threads: 16) { encoder in
            encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        }

        #expect(buffer[0] == -1, "カーネルは走らない (修正前と同じ)")
        #expect(context._warnedComputeOutsidePhase == ["dispatch"], "が、黙ってはいない")
    }

    @Test("compute() の外の computeBarrier も警告される")
    func computeBarrierOutsideComputeWarns() throws {
        let context = try makeContext()

        context.computeBarrier()

        #expect(context._warnedComputeOutsidePhase == ["computeBarrier"])
    }

    @Test("draw() から毎フレーム呼ばれてもログを埋めない")
    func warnsOncePerAPI() throws {
        let context = try makeContext()
        let kernel = try context.createComputeKernel(source: Self.fillSource, function: "fill")
        let buffer = try #require(context.createBuffer(count: 16, type: Float.self))

        // 1D・2D どちらの dispatch も利用者から見れば同じ `dispatch`。
        for _ in 0..<3 {
            context.dispatch(kernel, threads: 16) { encoder in
                encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
            }
            context.dispatch(kernel, width: 4, height: 4) { encoder in
                encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
            }
        }

        #expect(context._warnedComputeOutsidePhase == ["dispatch"])
    }

    // MARK: - 正しい場所から呼んだとき

    @Test("compute() の中では警告ゼロでカーネルが走る")
    func dispatchInsideComputeRuns() throws {
        let context = try makeContext()
        let kernel = try context.createComputeKernel(source: Self.fillSource, function: "fill")
        let buffer = try #require(context.createBuffer(count: 16, type: Float.self))
        buffer[0] = -1

        let commandBuffer = try #require(context.renderer.commandQueue.makeCommandBuffer())
        context.beginCompute(commandBuffer: commandBuffer, time: 0, deltaTime: 0)
        context.dispatch(kernel, threads: 16) { encoder in
            encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        }
        // dispatch 済みならバリアはエンコーダーへ届く。ここで警告が出ないことも確かめる。
        context.computeBarrier()
        context.endCompute()
        try MetalTestHelper.commit(commandBuffer)

        #expect(buffer[0] == 42)
        #expect(context._warnedComputeOutsidePhase.isEmpty, "正しい使い方に警告を出さない")
    }

    /// 利用者が実際に書く形 — `Sketch` 側のラッパ経由で `setup()` から呼ぶ。
    /// Issue #1092 の報告もこの形（GPU の初期化を `setup()` にまとめ、初期状態を
    /// カーネルで 1 回だけ埋めようとした）だった。
    @Test("Sketch の setup() から呼んでも同じ警告になる")
    func dispatchFromSketchSetupWarns() throws {
        let context = try makeContext()
        let sketch = ComputeInSetupSketch()
        sketch._context = context
        defer { sketch._context = nil }

        sketch.setup()

        #expect(sketch.valueAfterDispatch == -1, "カーネルは走らない")
        #expect(context._warnedComputeOutsidePhase == ["dispatch"])
    }

    @Test("compute() の中なら dispatch 前の computeBarrier も黙って通す")
    func barrierBeforeFirstDispatchIsSilent() throws {
        let context = try makeContext()

        let commandBuffer = try #require(context.renderer.commandQueue.makeCommandBuffer())
        context.beginCompute(commandBuffer: commandBuffer, time: 0, deltaTime: 0)
        // 順序を守る相手がまだ無いだけの無害な no-op。場所は間違っていないので警告しない。
        context.computeBarrier()
        context.endCompute()
        try MetalTestHelper.commit(commandBuffer)

        #expect(context._warnedComputeOutsidePhase.isEmpty)
    }
}

/// `setup()` で GPU まわりを全部済ませようとするスケッチ（Issue #1092 の報告の形）。
@MainActor
private final class ComputeInSetupSketch: Sketch {
    var valueAfterDispatch: Float = .nan

    func setup() {
        // カーネルもバッファも setup() で正しく作れる。
        guard
            let kernel = try? createComputeKernel(
                source: """
                    #include <metal_stdlib>
                    using namespace metal;
                    kernel void fill(device float *buf [[buffer(0)]],
                                     uint id [[thread_position_in_grid]]) {
                        buf[id] = 42.0;
                    }
                    """,
                function: "fill"),
            let buffer = createBuffer(count: 16, type: Float.self)
        else { return }
        buffer[0] = -1

        // ここだけが効かない。
        dispatch(kernel, threads: 16) { encoder in
            encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        }
        valueAfterDispatch = buffer[0]
    }

    func draw() {}
}
