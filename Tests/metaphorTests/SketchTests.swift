import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - SketchConfig Tests

@Suite("SketchConfig")
struct SketchConfigTests {

    @Test("default config values")
    func defaultValues() {
        let config = SketchConfig()
        #expect(config.width == 1920)
        #expect(config.height == 1080)
        #expect(config.title == "metaphor")
        #expect(config.fps == 60)
        #expect(config.legacySyphonName == nil, "旧 syphonName の実体は既定で nil（deprecated 窓）")
        #expect(config.windowScale == 0.5)
        #expect(config.preventAppNap == true)
    }

    @Test("custom config values")
    func customValues() {
        let config = SketchConfig(
            width: 1280,
            height: 720,
            title: "Test",
            fps: 30,
            windowScale: 1.0,
            preventAppNap: false
        )
        #expect(config.width == 1280)
        #expect(config.height == 720)
        #expect(config.title == "Test")
        #expect(config.fps == 30)
        #expect(config.windowScale == 1.0)
        #expect(config.preventAppNap == false)
    }
}

// MARK: - Deprecated Syphon fields（deprecation 窓・#1040）

/// 旧 `syphonName:` / `syphon:` を取る init と computed property は deprecated だが、M6 で削除するまで
/// 実体（`legacySyphon*`）へ落ちて metaphor-syphon の provider から読める。
/// deprecated な宣言の中では deprecation 警告が出ない（CI は `-warnings-as-errors`）ので、
/// テスト関数自体を deprecated にして旧 API を呼ぶ。
@Suite("SketchConfig deprecated Syphon fields")
struct SketchConfigDeprecatedSyphonTests {

    @available(*, deprecated)
    @Test("syphon: true は title 名の要求として実体へ落ちる")
    func syphonFlagInit() {
        let config = SketchConfig(title: "T", syphon: true)
        #expect(config.legacySyphonEnabled == true)
        #expect(config.legacySyphonName == nil)
        #expect(config.syphon == true)
    }

    @available(*, deprecated)
    @Test("syphonName: は名前として実体へ落ち、setter も実体を書く")
    func syphonNameInit() {
        var config = SketchConfig(title: "T", syphonName: "Preview")
        #expect(config.legacySyphonName == "Preview")
        #expect(config.syphonName == "Preview")
        config.syphonName = "Other"
        #expect(config.legacySyphonName == "Other")
        config.syphon = true
        #expect(config.legacySyphonEnabled == true)
    }

    @Test("新しい init（syphon 引数なし）は実体を空にする")
    func plainInitIsEmpty() {
        let config = SketchConfig(title: "T", fps: 30)
        #expect(config.legacySyphonEnabled == false)
        #expect(config.legacySyphonName == nil)
    }

    @available(*, deprecated)
    @Test("SketchWindowConfig(syphonName:) も実体へ落ちる")
    func windowConfig() {
        let config = SketchWindowConfig(title: "W", syphonName: "Win")
        #expect(config.legacySyphonName == "Win")
        #expect(config.syphonName == "Win")
        #expect(SketchWindowConfig(title: "W").legacySyphonName == nil)
    }
}

// MARK: - App Nap Prevention Tests

@Suite("App Nap prevention resolution")
struct AppNapPreventionTests {

    @Test("default config prevents App Nap")
    func defaultPrevents() {
        #expect(SketchRunner.resolvePreventAppNap(config: SketchConfig(), env: [:]))
    }

    @Test("preventAppNap: false opts out")
    func configOptOut() {
        let config = SketchConfig(preventAppNap: false)
        #expect(!SketchRunner.resolvePreventAppNap(config: config, env: [:]))
    }

    @Test("METAPHOR_ALLOW_APP_NAP=1 overrides config")
    func envOverridesConfig() {
        #expect(!SketchRunner.resolvePreventAppNap(
            config: SketchConfig(), env: ["METAPHOR_ALLOW_APP_NAP": "1"]
        ))
    }

    @Test("METAPHOR_ALLOW_APP_NAP with non-1 value is ignored")
    func envNonOneIgnored() {
        #expect(SketchRunner.resolvePreventAppNap(
            config: SketchConfig(), env: ["METAPHOR_ALLOW_APP_NAP": "0"]
        ))
        #expect(SketchRunner.resolvePreventAppNap(
            config: SketchConfig(), env: ["METAPHOR_ALLOW_APP_NAP": ""]
        ))
    }
}

// MARK: - FPS Resolution Tests

@Suite("FPS resolution")
struct FPSResolutionTests {

    @Test("falls back to config.fps when unset")
    func fallsBackToConfig() {
        #expect(SketchRunner.resolveFPS(config: SketchConfig(), env: [:]) == 60)
        #expect(SketchRunner.resolveFPS(config: SketchConfig(fps: 24), env: [:]) == 24)
    }

    @Test("METAPHOR_FPS overrides config")
    func envOverridesConfig() {
        #expect(SketchRunner.resolveFPS(
            config: SketchConfig(fps: 60), env: ["METAPHOR_FPS": "30"]
        ) == 30)
        // cli の `--fps` は下げるだけでなく上げる向きにも使うので両方向を固定する。
        #expect(SketchRunner.resolveFPS(
            config: SketchConfig(fps: 30), env: ["METAPHOR_FPS": "120"]
        ) == 120)
    }

    @Test("unparsable METAPHOR_FPS falls back to config.fps")
    func unparsableFallsBack() {
        let config = SketchConfig(fps: 45)
        // 0 以下・非数値・空文字は「無視して config へ」（起動しないより素直に動く方を選ぶ）。
        for raw in ["0", "-1", "abc", "", " 30", "30.0"] {
            #expect(
                SketchRunner.resolveFPS(config: config, env: ["METAPHOR_FPS": raw]) == 45,
                "METAPHOR_FPS=\(raw) should be ignored"
            )
        }
    }
}

// MARK: - Termination Signal Tests

/// 終了シグナル（#715）のハンドラ設置を検証します。
///
/// 実際に自プロセスへシグナルを送るため、シグナル動作（`SIG_IGN` / `SIG_DFL`）が
/// プロセス全体に及びます。他テストと重ならないよう `.serialized` で直列化します。
@Suite("Termination signal handlers", .serialized)
struct TerminationSignalTests {

    /// `onTerminate` が呼ばれたことを別スレッドから観測するためのフラグ。
    private final class TerminationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func fire() { lock.withLock { value = true } }
        var fired: Bool { lock.withLock { value } }
    }

    /// ハンドラを設置して `sig` を自プロセスへ送り、ハンドラが発火したかを返します。
    ///
    /// シグナル動作は必ず既定へ戻します（戻さないとテストランナー自体が
    /// `SIGTERM` を無視し続ける）。
    private func firesHandler(for sig: Int32) async -> Bool {
        let flag = TerminationFlag()
        let sources = SketchRunner.installTerminationSignalHandlers(env: [:]) { flag.fire() }
        defer {
            for source in sources { source.cancel() }
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }

        // DispatchSource は別キューで発火するため、送出後にポーリングで待つ（最大 2 秒）。
        kill(getpid(), sig)
        for _ in 0..<200 {
            if flag.fired { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("SIGTERM runs the graceful termination path")
    func sigtermFires() async {
        #expect(await firesHandler(for: SIGTERM))
    }

    @Test("SIGINT runs the graceful termination path")
    func sigintFires() async {
        #expect(await firesHandler(for: SIGINT))
    }

    @Test("handlers are installed by default")
    func installedByDefault() {
        #expect(SketchRunner.resolveInstallSignalHandlers(env: [:]))
    }

    @Test("METAPHOR_SIGNAL_HANDLERS=0 opts out")
    func envOptOut() {
        #expect(!SketchRunner.resolveInstallSignalHandlers(
            env: ["METAPHOR_SIGNAL_HANDLERS": "0"]
        ))
        #expect(SketchRunner.installTerminationSignalHandlers(
            env: ["METAPHOR_SIGNAL_HANDLERS": "0"]
        ).isEmpty)
    }

    @Test("METAPHOR_SIGNAL_HANDLERS with non-0 value is ignored")
    func envNonZeroIgnored() {
        #expect(SketchRunner.resolveInstallSignalHandlers(
            env: ["METAPHOR_SIGNAL_HANDLERS": "1"]
        ))
        #expect(SketchRunner.resolveInstallSignalHandlers(
            env: ["METAPHOR_SIGNAL_HANDLERS": ""]
        ))
    }
}

// MARK: - SketchContext Tests

@Suite("SketchContext", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextTests {

    @Test("context has correct dimensions")
    func dimensions() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.width == 1920)
        #expect(context.height == 1080)
    }

    @Test("context initial state")
    func initialState() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.time == 0)
        #expect(context.deltaTime == 0)
        #expect(context.frameCount == 0)
    }

    @Test("context exposes renderer")
    func escapteHatch() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.renderer === renderer)
        #expect(context.canvas === canvas)
        #expect(context.input === renderer.input)
    }

    @Test("context encoder is nil outside frame")
    func encoderOutsideFrame() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.encoder == nil)
    }

    @Test("loop and noLoop callbacks fire only on state transitions")
    func loopNoLoopCallbacksAreIdempotent() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        var loopCount = 0
        var noLoopCount = 0
        context.onLoop = { loopCount += 1 }
        context.onNoLoop = { noLoopCount += 1 }

        context.noLoop()
        context.noLoop()
        context.loop()
        context.loop()

        #expect(noLoopCount == 1)
        #expect(loopCount == 1)
        #expect(context.isLooping)
    }
}

// MARK: - SketchContext Compute Tests

@Suite("SketchContext Compute", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextComputeTests {

    @Test("createComputeKernel compiles MSL source")
    func createKernel() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void test(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 1.0;
        }
        """
        let kernel = try context.createComputeKernel(source: source, function: "test")
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
    }

    @Test("createBuffer creates typed GPU buffer")
    func createTypedBuffer() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let buf = context.createBuffer(count: 100, type: Float.self)
        #expect(buf != nil)
        #expect(buf!.count == 100)
    }

    @Test("createBuffer from array preserves data")
    func createBufferFromArray() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let data: [Float] = [1, 2, 3, 4, 5]
        let buf = context.createBuffer(data)
        #expect(buf != nil)
        #expect(buf![2] == 3.0)
    }
}

// MARK: - Sketch Context Storage Tests (#135)

/// ストレージテスト用の最小 Sketch。
@MainActor
private final class StorageTestSketch: Sketch {
    func draw() {}
}

@Suite("Sketch context storage", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextStorageTests {

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
    }

    @Test("assigning nil removes the storage entry")
    func nilRemovesEntry() throws {
        let sketch = StorageTestSketch()
        let context = try makeContext()
        sketch._context = context
        #expect(sketch._context === context)

        // teardown 経路: nil 代入でストレージからエントリが削除される
        sketch._context = nil
        #expect(sketch._context == nil)
    }

    @Test("a fresh sketch never picks up a stale context after others are deallocated")
    func noStaleContextPickup() throws {
        let context = try makeContext()

        // _context を張ったまま Sketch を大量に解放する（teardown 忘れを模擬）。
        // 旧実装（ObjectIdentifier キーの辞書 + 削除なし）ではアドレス再利用に
        // より、新しいインスタンスが他人の stale context を拾い得た
        for _ in 0..<64 {
            let s = StorageTestSketch()
            s._context = context
        }

        let fresh = StorageTestSketch()
        #expect(fresh._context == nil)
    }

    @Test("storage does not keep the context alive after the sketch deallocates")
    func contextReleasedAfterSketchDealloc() throws {
        weak var weakContext: SketchContext?
        do {
            var sketch: StorageTestSketch? = StorageTestSketch()
            var context: SketchContext? = try makeContext()
            weakContext = context
            sketch?._context = context
            context = nil
            #expect(weakContext != nil)
            // Sketch 解放前に明示的に teardown（決定的に検証できる経路）
            sketch?._context = nil
            sketch = nil
        }
        #expect(weakContext == nil)
    }
}
