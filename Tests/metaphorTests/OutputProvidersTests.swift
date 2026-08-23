import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Fake providers

/// 環境変数 `FAKE_OUTPUT_<KEY>=1` のときだけ出力を返す provider。
///
/// 登録はプロセス全体で共有されるため、他スイートが `makeOutputs` を呼んでも反応しないよう
/// 環境変数でゲートする（テスト側は env を注入できる）。
struct FakeOutputProvider: MetaphorOutputProvider {
    let id: String
    let key: String
    let requirements: PluginRequirements
    let recorder: PostOrderRecorder

    @MainActor
    func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin? {
        guard context.environment["FAKE_OUTPUT_\(key)"] == "1" else { return nil }
        return OrderingOutputPlugin(id: id, recorder: recorder)
    }
}

private func primaryContext(
    _ config: SketchConfig = SketchConfig(), env: [String: String] = [:], isHeadless: Bool = false
) -> MetaphorOutputContext {
    MetaphorOutputContext(scope: .primary(config), environment: env, isHeadless: isHeadless)
}

// MARK: - Provider registry

@Suite("MetaphorOutputProviders", .serialized)
@MainActor
struct OutputProvidersTests {

    @Test("登録した provider は全部走査され、出力 plugin は通常 plugin の post() の後に走る")
    func multipleProvidersAllAttach() throws {
        try #require(MetalTestHelper.isGPUAvailable)
        let rec = PostOrderRecorder()
        let a = FakeOutputProvider(
            id: "fake-a", key: "A", requirements: [.externalRenderLoop], recorder: rec)
        let b = FakeOutputProvider(id: "fake-b", key: "B", requirements: [], recorder: rec)
        MetaphorOutputProviders.register(a)
        MetaphorOutputProviders.register(b)
        defer {
            MetaphorOutputProviders.unregister(id: "fake-a")
            MetaphorOutputProviders.unregister(id: "fake-b")
        }

        let outputs = MetaphorOutputProviders.makeOutputs(
            context: primaryContext(env: ["FAKE_OUTPUT_A": "1", "FAKE_OUTPUT_B": "1"])
        ).filter { $0.providerID.hasPrefix("fake-") }
        #expect(outputs.map(\.providerID) == ["fake-a", "fake-b"], "登録順に走査され、後勝ちで上書きされない")
        #expect(outputs[0].requirements == [.externalRenderLoop])
        #expect(outputs[1].requirements == [])

        let config = SketchConfig()
        let requirements = SketchRunner.aggregateRequirements(config: config, outputs: outputs)
        #expect(requirements.contains(.externalRenderLoop), "要件は provider ごとの宣言の和")

        let renderer = try MetaphorRenderer(width: 32, height: 32)
        renderer.addPlugin(OrderingPlugin(id: "normal", recorder: rec))
        for output in outputs { renderer.addPlugin(output.plugin) }
        renderer.renderFrame()
        #expect(rec.order == ["normal", "fake-a", "fake-b"], "両方の出力が post の最後に走る")
    }

    @Test("nil を返した provider は出力に含まれない")
    func providerReturningNilIsSkipped() {
        let rec = PostOrderRecorder()
        MetaphorOutputProviders.register(
            FakeOutputProvider(
                id: "fake-nil", key: "NIL", requirements: [.externalRenderLoop], recorder: rec)
        )
        defer { MetaphorOutputProviders.unregister(id: "fake-nil") }

        let outputs = MetaphorOutputProviders.makeOutputs(context: primaryContext())
        #expect(!outputs.contains { $0.providerID == "fake-nil" })
    }

    @Test("同じ id の再登録は置換（二重登録にならない）")
    func reregisterReplaces() {
        let rec = PostOrderRecorder()
        MetaphorOutputProviders.register(
            FakeOutputProvider(id: "fake-dup", key: "OLD", requirements: [], recorder: rec)
        )
        MetaphorOutputProviders.register(
            FakeOutputProvider(
                id: "fake-dup", key: "NEW", requirements: [.externalRenderLoop], recorder: rec)
        )
        defer { MetaphorOutputProviders.unregister(id: "fake-dup") }

        #expect(MetaphorOutputProviders.registered.filter { $0.id == "fake-dup" }.count == 1)
        #expect(
            MetaphorOutputProviders.makeOutputs(
                context: primaryContext(env: ["FAKE_OUTPUT_OLD": "1"])
            )
            .contains { $0.providerID == "fake-dup" } == false,
            "置換前の provider は反応しない"
        )
        let replaced = MetaphorOutputProviders.makeOutputs(
            context: primaryContext(env: ["FAKE_OUTPUT_NEW": "1"])
        ).first { $0.providerID == "fake-dup" }
        #expect(replaced?.requirements == [.externalRenderLoop], "置換後の provider が効く")
    }

    @Test("unregister 後は走査に現れない")
    func unregisterRemoves() {
        let rec = PostOrderRecorder()
        MetaphorOutputProviders.register(
            FakeOutputProvider(id: "fake-gone", key: "GONE", requirements: [], recorder: rec)
        )
        MetaphorOutputProviders.unregister(id: "fake-gone")
        #expect(!MetaphorOutputProviders.registered.contains { $0.id == "fake-gone" })
        #expect(
            !MetaphorOutputProviders.makeOutputs(
                context: primaryContext(env: ["FAKE_OUTPUT_GONE": "1"])
            )
            .contains { $0.providerID == "fake-gone" }
        )
    }
}

// MARK: - Context

@Suite("MetaphorOutputContext")
struct OutputContextTests {

    @Test("scope の便宜アクセサ")
    func scopeAccessors() {
        let primary = primaryContext(SketchConfig(title: "P"))
        #expect(primary.sketchConfig?.title == "P")
        #expect(primary.windowConfig == nil)

        let window = MetaphorOutputContext(
            scope: .window(SketchWindowConfig(title: "W")), environment: [:], isHeadless: true
        )
        #expect(window.windowConfig?.title == "W")
        #expect(window.sketchConfig == nil)
        #expect(window.isHeadless)
    }
}

// MARK: - Render loop resolution

@Suite("RenderLoopMode.resolve（宣言的な要件からの loop 決定）")
struct RenderLoopResolutionTests {

    @Test("ヘッドレスは displayLink を要件に関わらず実効 fps の timer へ倒す")
    func headlessFallsBackToTimer() {
        #expect(
            RenderLoopMode.resolve(
                requested: .displayLink, fps: 30, requirements: [], isHeadless: true)
                == .timer(fps: 30))
        #expect(
            RenderLoopMode.resolve(
                requested: .displayLink, fps: 30, requirements: [.externalRenderLoop],
                isHeadless: true) == .timer(fps: 30))
    }

    @Test("ヘッドレスでも明示された timer(fps:) は実効 fps に潰されない")
    func headlessKeepsExplicitTimerFPS() {
        // ウィンドウ経路と同じ結論になること（同じ設定が経路でレートを変えない）。#1063
        #expect(
            RenderLoopMode.resolve(
                requested: .timer(fps: 30), fps: 60, requirements: [], isHeadless: true)
                == .timer(fps: 30))
        #expect(
            RenderLoopMode.resolve(
                requested: .timer(fps: 30), fps: 60, requirements: [.externalRenderLoop],
                isHeadless: true) == .timer(fps: 30))
    }

    @Test("displayLink + externalRenderLoop → timer(fps)、要件なし → 据え置き、明示 timer は不変")
    func windowedResolution() {
        #expect(
            RenderLoopMode.resolve(
                requested: .displayLink, fps: 60, requirements: [.externalRenderLoop],
                isHeadless: false) == .timer(fps: 60))
        #expect(
            RenderLoopMode.resolve(
                requested: .displayLink, fps: 60, requirements: [], isHeadless: false)
                == .displayLink)
        #expect(
            RenderLoopMode.resolve(
                requested: .timer(fps: 24), fps: 60, requirements: [.externalRenderLoop],
                isHeadless: false) == .timer(fps: 24))
        #expect(
            RenderLoopMode.resolve(
                requested: .timer(fps: 24), fps: 60, requirements: [], isHeadless: false)
                == .timer(fps: 24))
    }

    @Test("SketchRunner.resolveLoopMode は config.renderLoopMode と実効 fps を使う")
    func runnerDelegates() {
        let config = SketchConfig(fps: 60, renderLoopMode: .displayLink)
        #expect(
            SketchRunner.resolveLoopMode(
                config: config, fps: 45, requirements: [.externalRenderLoop], isHeadless: false)
                == .timer(fps: 45))
        #expect(
            SketchRunner.resolveLoopMode(
                config: config, fps: 45, requirements: [], isHeadless: false) == .displayLink)
        #expect(
            SketchRunner.resolveLoopMode(
                config: config, fps: 45, requirements: [], isHeadless: true) == .timer(fps: 45))

        // 明示 timer は実効 fps（METAPHOR_FPS / config.fps）より優先される。#1063
        let explicitTimer = SketchConfig(fps: 60, renderLoopMode: .timer(fps: 30))
        #expect(
            SketchRunner.resolveLoopMode(
                config: explicitTimer, fps: 45, requirements: [], isHeadless: true)
                == .timer(fps: 30))
    }

    @Test("SketchRunner.aggregateRequirements は config.plugins と出力の要件の和")
    @MainActor
    func runnerAggregates() {
        let rec = PostOrderRecorder()
        let none = SketchConfig(plugins: [PluginFactory { MockPlugin(id: "plain") }])
        #expect(SketchRunner.aggregateRequirements(config: none, outputs: []).isEmpty)

        let declared = SketchConfig(plugins: [
            PluginFactory(requirements: [.externalRenderLoop]) { MockPlugin(id: "ext") }
        ])
        #expect(
            SketchRunner.aggregateRequirements(config: declared, outputs: []) == [
                .externalRenderLoop
            ])

        let output = MetaphorOutputProviders.ResolvedOutput(
            providerID: "x", plugin: OrderingOutputPlugin(id: "x", recorder: rec),
            requirements: [.externalRenderLoop]
        )
        #expect(
            SketchRunner.aggregateRequirements(config: none, outputs: [output]) == [
                .externalRenderLoop
            ])
    }

    @Test("出力が要求されたのに provider が無いときだけ診断を出す")
    func outputRequestedButMissing() {
        // 要求の入口は METAPHOR_SYPHON_NAME だけ（旧 SketchConfig.syphon / syphonName は v0.13.0 で削除）。
        #expect(!SketchRunner.outputRequestedButMissing(env: [:], isHeadless: false, outputs: []))
        #expect(
            SketchRunner.outputRequestedButMissing(
                env: ["METAPHOR_SYPHON_NAME": "n"], isHeadless: false, outputs: []))
        #expect(
            !SketchRunner.outputRequestedButMissing(
                env: ["METAPHOR_SYPHON_NAME": ""], isHeadless: false, outputs: []),
            "空文字の環境変数は未設定")
        // ヘッドレス: viewer socket も Probe も出力も無いときだけ error 級（何も見えないプロセスになる）。
        #expect(SketchRunner.outputRequestedButMissing(env: [:], isHeadless: true, outputs: []))
        #expect(
            !SketchRunner.outputRequestedButMissing(
                env: ["METAPHOR_VIEWER_SOCKET": "/tmp/v.sock"], isHeadless: true, outputs: []
            ), "viewer socket があれば観測手段がある")
        #expect(
            !SketchRunner.outputRequestedButMissing(
                env: ["METAPHOR_PROBE": "1"], isHeadless: true, outputs: []
            ), "Probe があれば観測手段がある")
        #expect(
            SketchRunner.outputRequestedButMissing(
                env: ["METAPHOR_VIEWER_SOCKET": ""], isHeadless: true, outputs: []
            ), "空文字の socket パスは未設定")
    }

    @Test("ViewerOutputProvider は METAPHOR_VIEWER_SOCKET があるプライマリだけに出力を返す")
    @MainActor
    func viewerOutputProvider() {
        let provider = ViewerOutputProvider()
        #expect(provider.id == ViewerOutputPlugin.id)
        #expect(provider.requirements == [.externalRenderLoop])

        #expect(provider.makeOutput(context: primaryContext()) == nil)
        #expect(
            provider.makeOutput(context: primaryContext(env: ["METAPHOR_VIEWER_SOCKET": ""])) == nil
        )
        let output = provider.makeOutput(
            context: primaryContext(env: ["METAPHOR_VIEWER_SOCKET": "/tmp/v.sock"]))
        #expect((output as? ViewerOutputPlugin)?.socketPath == "/tmp/v.sock")

        let window = MetaphorOutputContext(
            scope: .window(SketchWindowConfig()),
            environment: ["METAPHOR_VIEWER_SOCKET": "/tmp/v.sock"], isHeadless: true
        )
        #expect(provider.makeOutput(context: window) == nil, "セカンダリウィンドウはビューアに出さない")

        // SketchRunner が登録すると走査に現れる（同 id は置換されるので何度でも）。
        ViewerOutputProvider.register()
        ViewerOutputProvider.register()
        #expect(
            MetaphorOutputProviders.registered.filter { $0.id == ViewerOutputPlugin.id }.count == 1)
    }
}

// MARK: - PluginFactory requirements

@Suite("PluginFactory.requirements")
struct PluginFactoryRequirementsTests {

    @Test("既定は空で、従来の trailing closure の形が通る")
    @MainActor
    func defaultIsEmpty() {
        let factory = PluginFactory { MockPlugin(id: "default") }
        #expect(factory.requirements.isEmpty)
        #expect(factory.create().pluginID == "default")
    }

    @Test("requirements: を宣言でき、生成されるインスタンスは変わらない")
    @MainActor
    func declaredRequirements() {
        let factory = PluginFactory(requirements: [.externalRenderLoop]) {
            MockPlugin(id: "declared")
        }
        #expect(factory.requirements == [.externalRenderLoop])
        #expect(factory.create().pluginID == "declared")
    }
}
