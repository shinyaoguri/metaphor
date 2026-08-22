import Testing
import Metal
import Foundation
import os
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - 観測・操作機構のランタイム性能「非侵害」ガード（Issue #118）
//
// 設計上の性能契約:
//   - OFF（Probe/入力注入プラグイン未登録 = 通常実行）: `probe(...)` は完全 no-op、
//     フレームループのプラグイン配列は空でゼロコスト。
//   - ON（MCP/ヘッドレス経由で登録）: `pre()` は毎フレーム軽量（stat + reset）、
//     `post()` はリクエストが無い間は即 return。重い readback/PNG/JSON は
//     オンデマンドかつ描画スレッド外（`deferReadback`/completion handler）。
//
// これらのテストは上記が将来のリファクタで回帰しないことを守る。桁が変わる劣化
// （例: `probe()` が呼び出しごとに線形走査に戻る、idle の `pre()`/`post()` が
// 同期 I/O を始める）を捕捉するのが目的で、絶対性能のベンチではない。

// MARK: - Probe プラグインキャッシュの正当性

/// `MetaphorRenderer.probePlugin` は `probe(...)` のホットパス用キャッシュ。
/// 登録・解除でのみ更新され、`probe(...)` 呼び出しごとの `plugins` 線形走査を排除する。
@Suite("ObservabilityOverhead: probe plugin cache", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ProbePluginCacheTests {

    private func makeIdleProbePlugin(_ dir: URL) -> MetaphorProbePlugin {
        MetaphorProbePlugin(
            config: MetaphorProbeConfig(
                outputDirectory: dir.appendingPathComponent("current").path,
                requestFilePath: dir.appendingPathComponent("request.json").path
            )
        )
    }

    @Test("プラグイン未登録なら probePlugin は nil（probe() は no-op）")
    func emptyRendererHasNoProbePlugin() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        #expect(renderer.probePlugin == nil)
    }

    @Test("Probe プラグイン登録でキャッシュが同一インスタンスを指す")
    func addingProbePluginPopulatesCache() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let renderer = try MetaphorRenderer(width: 32, height: 32)
            let plugin = makeIdleProbePlugin(dir)
            renderer.addPlugin(plugin)
            #expect(renderer.probePlugin === plugin)
        }
    }

    @Test("Probe 以外のプラグインではキャッシュは nil のまま")
    func nonProbePluginDoesNotPopulateCache() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        renderer.addPlugin(MockPlugin(id: "not-a-probe"))
        renderer.addPlugin(InputInjectionPlugin(lineSource: { nil }))
        #expect(renderer.probePlugin == nil)
    }

    @Test("Probe プラグイン解除でキャッシュがクリアされる")
    func removingProbePluginClearsCache() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let renderer = try MetaphorRenderer(width: 32, height: 32)
            let plugin = makeIdleProbePlugin(dir)
            renderer.addPlugin(plugin)
            #expect(renderer.probePlugin === plugin)

            renderer.removePlugin(id: MetaphorProbePlugin.id)
            #expect(renderer.probePlugin == nil)
        }
    }

    @Test("shutdown でキャッシュがクリアされる")
    func shutdownClearsCache() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let renderer = try MetaphorRenderer(width: 32, height: 32)
            renderer.addPlugin(makeIdleProbePlugin(dir))
            #expect(renderer.probePlugin != nil)

            renderer.shutdown()
            #expect(renderer.probePlugin == nil)
        }
    }
}

// MARK: - Sketch.probe() の OFF=no-op / ON=記録 経路

/// `probe(...)` を呼ぶだけの最小スケッチ（プロトコル既定実装で全要件を満たす）。
@MainActor
private final class BareSketch: Sketch {}

@Suite("ObservabilityOverhead: Sketch.probe routing", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchProbeRoutingTests {

    private func makeContext() throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        return (renderer, context)
    }

    @Test("OFF: probe() はプラグイン未登録なら完全 no-op")
    func probeIsNoOpWhenOff() throws {
        let (renderer, context) = try makeContext()
        let sketch = BareSketch()
        sketch._context = context

        #expect(renderer.probePlugin == nil)
        // 未登録でも安全に呼べ、観測可能な副作用を持たない。
        for i in 0..<1000 {
            sketch.probe("particles.count", i)
            sketch.probe("phase", "idle")
        }
        #expect(renderer.probePlugin == nil)
    }

    @Test("ON: probe() はキャッシュ経路でプラグインの state buffer に記録される")
    func probeRecordsWhenOn() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let (renderer, context) = try makeContext()
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: dir.appendingPathComponent("current").path,
                    requestFilePath: dir.appendingPathComponent("request.json").path
                )
            )
            renderer.addPlugin(plugin)

            let sketch = BareSketch()
            sketch._context = context

            sketch.probe("particles.count", 42)
            sketch.probe("phase", "spawning")

            let values = plugin.stateBuffer.values
            #expect(values["particles.count"]?.typeTag == "int")
            #expect(values["phase"]?.typeTag == "string")
            #expect(values.count == 2)
        }
    }
}

// MARK: - idle ホットパスのコストと副作用ゼロ

@Suite("ObservabilityOverhead: idle hot path", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct IdleHotPathTests {

    /// 壁時計しきい値の検証を行うか（既定 OFF）。
    ///
    /// 共有 macOS ランナーの負荷次第で揺れるため、`PerformanceBenchmarks`（#149）と
    /// 同じ `METAPHOR_PERF_TESTS=1` ゲートで必須チェックから分離している。
    /// このテストの本体（idle が出力を一切作らないこと）は常に検証される。
    private static let checksWallClock =
        ProcessInfo.processInfo.environment["METAPHOR_PERF_TESTS"] == "1"

    private func measure(_ body: () throws -> Void) rethrows -> Duration {
        try ContinuousClock().measure(body)
    }

    /// post() は pendingRequest が無い間 texture に触れず即 return するが、
    /// シグネチャ上テクスチャが要るのでダミーを1枚用意する。
    private func makeDummyTexture(_ device: MTLDevice) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        return try #require(device.makeTexture(descriptor: desc))
    }

    @Test("ON・リクエスト無し: pre()/post() を多数回回しても出力を作らず低コスト")
    func idlePrePostIsCheapAndSideEffectFree() throws {
        try TempFileHelper.withTemporaryDirectory { dir in
            let outputDir = dir.appendingPathComponent("current")
            let plugin = MetaphorProbePlugin(
                config: MetaphorProbeConfig(
                    outputDirectory: outputDir.path,
                    // request.json は一度も書かない = 常に idle 経路。
                    requestFilePath: dir.appendingPathComponent("request.json").path
                )
            )
            let renderer = try MetaphorRenderer(width: 64, height: 64)
            renderer.addPlugin(plugin)

            let cb = try #require(renderer.commandQueue.makeCommandBuffer())
            let tex = try makeDummyTexture(renderer.device)

            let iterations = 5000
            let elapsed = measure {
                for _ in 0..<iterations {
                    plugin.pre(commandBuffer: cb, time: 0)
                    plugin.post(texture: tex, commandBuffer: cb)
                }
            }

            // リクエストが無い間は frame.png も sequence/ も一切作られない。
            #expect(!FileManager.default.fileExists(
                atPath: outputDir.appendingPathComponent("frame.png").path
            ))
            #expect(!FileManager.default.fileExists(
                atPath: outputDir.appendingPathComponent("sequence").path
            ))

            // 桁変化の劣化ガード（同期 readback 混入等）。CI 変動を見込んだ緩い上限:
            // 5000 反復で 2 秒未満（= 1 反復あたり 400µs 未満）。実測はこれより桁違いに小さい。
            // 壁時計依存なので opt-in（METAPHOR_PERF_TESTS=1）でのみ検証する（#149 / #329）。
            if Self.checksWallClock {
                #expect(elapsed < .seconds(2), "idle pre()/post() ×\(iterations) took \(elapsed)")
            }
        }
    }
}

// MARK: - viewer 出力（未接続）は idle

@Suite("ObservabilityOverhead: idle viewer output", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct IdleViewerOutputTests {

    /// `METAPHOR_VIEWER_SOCKET` に親がいない（接続失敗）`ViewerOutputPlugin` は、`post()` で
    /// 共有メモリも blit も作らず即 return する（通常実行では登録すらされないのでゼロコスト）。
    @Test("未接続の ViewerOutputPlugin は pre()/post() を回しても何も作らない")
    func unconnectedViewerOutputIsInert() throws {
        let plugin = ViewerOutputPlugin(socketPath: "/nonexistent/metaphor-viewer-idle.sock")
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        renderer.addPlugin(plugin)
        #expect(!plugin.isConnected)

        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let tex = try #require(renderer.device.makeTexture(descriptor: desc))

        for _ in 0..<5000 {
            plugin.pre(commandBuffer: cb, time: 0)
            plugin.post(texture: tex, commandBuffer: cb)
        }
        // blit encoder を 1 つも積んでいなければ、コマンドバッファはそのまま commit できる。
        cb.commit()
        cb.waitUntilCompleted()
        #expect(cb.status == .completed)
    }
}

// MARK: - 入力注入 idle は dispatch しない

@Suite("ObservabilityOverhead: idle input injection", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct IdleInputInjectionTests {

    @Test("イベントが無ければ pre() は InputManager を変更しない")
    func idlePreDoesNotDispatch() throws {
        let renderer = try MetaphorRenderer(width: 100, height: 100)
        // lineSource が常に nil = イベントは一切来ない。
        let plugin = InputInjectionPlugin(lineSource: { nil })
        renderer.addPlugin(plugin)

        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        for _ in 0..<2000 {
            plugin.pre(commandBuffer: cb, time: 0)
        }

        #expect(renderer.input.mouseX == 0)
        #expect(renderer.input.mouseY == 0)
        #expect(!renderer.input.isMouseDown)
        #expect(!renderer.input.isKeyPressed)
    }
}
