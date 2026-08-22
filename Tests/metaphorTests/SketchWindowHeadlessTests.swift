import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore

// MARK: - 環境変数・ループモードの解決（純粋関数）

@Suite("SketchWindow headless: 解決規則")
struct SketchWindowHeadlessResolutionTests {

    @Test("METAPHOR_VIEWER=1 のときだけヘッドレス")
    func resolveHeadless() {
        #expect(SketchWindow.resolveHeadless(env: [:]) == false)
        #expect(SketchWindow.resolveHeadless(env: ["METAPHOR_VIEWER": "1"]) == true)
        #expect(SketchWindow.resolveHeadless(env: ["METAPHOR_VIEWER": "0"]) == false)
        #expect(SketchWindow.resolveHeadless(env: ["METAPHOR_VIEWER": ""]) == false)
    }

    @Test("ヘッドレスは displayLink 指定でも常にタイマー駆動になる")
    func headlessAlwaysUsesTimer() {
        let config = SketchWindowConfig(fps: 30, renderLoopMode: .displayLink)
        #expect(
            SketchWindow.resolveLoopMode(config: config, requirements: [], isHeadless: true)
                == .timer(fps: 30)
        )
    }

    @Test("ウィンドウ表示では従来どおりの解決（外部ループを要する出力があるときだけタイマーへ）")
    func windowedResolutionIsUnchanged() {
        let plain = SketchWindowConfig(fps: 60, renderLoopMode: .displayLink)
        #expect(
            SketchWindow.resolveLoopMode(config: plain, requirements: [], isHeadless: false)
                == .displayLink
        )

        // syphonName ありは Syphon provider が .externalRenderLoop を宣言する（集計結果で timer へ）。
        let syphon = SketchWindowConfig(fps: 60, syphonName: "test", renderLoopMode: .displayLink)
        #expect(
            SketchWindow.resolveLoopMode(
                config: syphon, requirements: [.externalRenderLoop], isHeadless: false
            ) == .timer(fps: 60)
        )

        let explicitTimer = SketchWindowConfig(fps: 24, renderLoopMode: .timer(fps: 24))
        #expect(
            SketchWindow.resolveLoopMode(
                config: explicitTimer, requirements: [.externalRenderLoop], isHeadless: false
            ) == .timer(fps: 24)
        )
    }

    @Test("config.plugins の要件が集計に入る（externalRenderLoop を宣言したファクトリで timer へ）")
    func pluginRequirementsAreAggregated() {
        let config = SketchWindowConfig(
            fps: 60, renderLoopMode: .displayLink,
            plugins: [PluginFactory(requirements: [.externalRenderLoop]) { MockPlugin(id: "ext") }]
        )
        let requirements = SketchWindow.aggregateRequirements(config: config, outputs: [])
        #expect(requirements.contains(.externalRenderLoop))
        #expect(
            SketchWindow.resolveLoopMode(config: config, requirements: requirements, isHeadless: false)
                == .timer(fps: 60)
        )

        let none = SketchWindowConfig(plugins: [PluginFactory { MockPlugin(id: "plain") }])
        #expect(SketchWindow.aggregateRequirements(config: none, outputs: []).isEmpty)
    }
}

// MARK: - 実インスタンス

// ヘッドレス側だけを実際に構築する。非ヘッドレスは `makeKeyAndOrderFront` で画面に
// ウィンドウを出すため、テストからは構築しない。
@Suite("SketchWindow headless: 実インスタンス", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchWindowHeadlessInstanceTests {

    @Test("ヘッドレスでは NSWindow を作らない")
    func doesNotCreateNativeWindow() throws {
        let shared = try SharedMetalResources()
        let window = try SketchWindow(
            config: SketchWindowConfig(width: 64, height: 64, title: "headless-test"),
            sharedResources: shared,
            isHeadless: true
        )
        defer { window.close() }

        #expect(window.hasNativeWindow == false)
        #expect(window.isOpen == true)
    }

    @Test("SketchWindowConfig(plugins:) のファクトリはこのウィンドウのレンダラーへ attach される")
    func configPluginsAttachToWindowRenderer() throws {
        let shared = try SharedMetalResources()
        let plugin = MockPlugin(id: "window-config-plugin")
        let window = try SketchWindow(
            config: SketchWindowConfig(
                width: 64, height: 64, title: "headless-plugins",
                plugins: [PluginFactory { plugin }]
            ),
            sharedResources: shared,
            isHeadless: true
        )
        defer { window.close() }

        #expect(plugin.attachedRenderer != nil, "onAttach(renderer:) がウィンドウ生成時に呼ばれる")
        #expect(plugin.attachedSketch == nil, "セカンダリには Sketch が無いので onAttach(sketch:) は呼ばれない")
    }

    @Test("ヘッドレスでも描画クロージャは呼ばれる")
    func keepsRenderingWithoutWindow() async throws {
        let shared = try SharedMetalResources()
        let window = try SketchWindow(
            config: SketchWindowConfig(width: 64, height: 64, title: "headless-render"),
            sharedResources: shared,
            isHeadless: true
        )
        defer { window.close() }

        final class Counter: @unchecked Sendable { var value = 0 }
        let drawn = Counter()
        window.onDraw { _ in drawn.value += 1 }

        // タイマー駆動のレンダーループが 1 フレーム以上回るのを待つ（既定 60fps）。
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(drawn.value > 0)
    }
}
