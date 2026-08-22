import Testing
@testable import MetaphorCore
@testable import MetaphorSyphon

// Syphon の自動配線（名前解決と provider の判定）を固定する。
// S0（#1039）で MetaphorSyphon が独立リポジトリへ移るとき、このファイルごと持ち出せるよう
// MetaphorCore の公開 API と MetaphorSyphon の internal だけに依存させる。

// MARK: - 名前解決（SketchRunner.resolveSyphonName から移設）

@Suite("Syphon output name resolution")
struct SyphonOutputNameResolutionTests {

    @Test("no output by default")
    func disabledByDefault() {
        #expect(SyphonOutputProvider.resolveSyphonName(config: SketchConfig(), env: [:]) == nil)
    }

    @Test("precedence: env > syphonName > (syphon ? title : nil)")
    func precedence() {
        let config = SketchConfig(title: "MyTitle", syphonName: "FromConfig", syphon: true)

        // 1 段目: 環境変数が最優先。
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: config, env: ["METAPHOR_SYPHON_NAME": "FromEnv"]
        ) == "FromEnv")

        // 2 段目: 環境変数が無ければ config.syphonName。
        #expect(SyphonOutputProvider.resolveSyphonName(config: config, env: [:]) == "FromConfig")

        // 3 段目: syphonName も無ければ syphon フラグ次第で title。
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle", syphon: true), env: [:]
        ) == "MyTitle")
    }

    @Test("syphonName alone enables output")
    func syphonNameImpliesEnabled() {
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(syphonName: "Named", syphon: false), env: [:]
        ) == "Named")
    }

    @Test("empty METAPHOR_SYPHON_NAME is treated as unset")
    func emptyEnvIsUnset() {
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(syphonName: "FromConfig"),
            env: ["METAPHOR_SYPHON_NAME": ""]
        ) == "FromConfig")
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(), env: ["METAPHOR_SYPHON_NAME": ""]
        ) == nil)
        // ヘッドレスでも同じ（= 名前が "" のサーバーを publish しない）。
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle"),
            env: ["METAPHOR_SYPHON_NAME": ""], requiresOutput: true
        ) == "MyTitle")
    }

    @Test("windowed path yields nil when nothing asks for output")
    func windowedWithoutOutputIsNil() {
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle", syphon: false), env: [:]
        ) == nil)
    }

    @Test("requiresOutput: true (headless) always resolves a name")
    func headlessAlwaysResolves() {
        // ヘッドレスは「ウィンドウ無し・出力のみ」なので、syphon フラグ抜きでも title へ落とす。
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle", syphon: false),
            env: [:], requiresOutput: true
        ) == "MyTitle")

        // 優先順位そのものは requiresOutput では変わらない。
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle", syphonName: "FromConfig"),
            env: [:], requiresOutput: true
        ) == "FromConfig")
        #expect(SyphonOutputProvider.resolveSyphonName(
            config: SketchConfig(title: "MyTitle", syphonName: "FromConfig"),
            env: ["METAPHOR_SYPHON_NAME": "FromEnv"], requiresOutput: true
        ) == "FromEnv")
    }
}

// MARK: - provider の判定

@Suite("SyphonOutputProvider")
struct SyphonOutputProviderTests {

    @Test("id と要件（外部ループ）")
    func identity() {
        let provider = SyphonOutputProvider()
        #expect(provider.id == "org.metaphor.syphon")
        #expect(provider.requirements == [.externalRenderLoop])
    }

    @Test("プライマリ: env > syphonName > syphon フラグ、ヘッドレスは title へ落ちる")
    func primaryScope() {
        func name(_ config: SketchConfig, env: [String: String] = [:], headless: Bool = false) -> String? {
            SyphonOutputProvider.resolveOutputName(context: MetaphorOutputContext(
                scope: .primary(config), environment: env, isHeadless: headless
            ))
        }
        #expect(name(SketchConfig(title: "T")) == nil)
        #expect(name(SketchConfig(title: "T", syphon: true)) == "T")
        #expect(name(SketchConfig(title: "T", syphonName: "N")) == "N")
        #expect(name(SketchConfig(title: "T", syphonName: "N"), env: ["METAPHOR_SYPHON_NAME": "E"]) == "E")
        #expect(name(SketchConfig(title: "T"), headless: true) == "T", "ヘッドレスは出力しか無いので必ず publish する")
    }

    @Test("セカンダリウィンドウ: syphonName だけを見る（env / syphon フラグは見ない）")
    func windowScope() {
        func name(_ config: SketchWindowConfig, env: [String: String] = [:], headless: Bool = false) -> String? {
            SyphonOutputProvider.resolveOutputName(context: MetaphorOutputContext(
                scope: .window(config), environment: env, isHeadless: headless
            ))
        }
        #expect(name(SketchWindowConfig(syphonName: "W")) == "W")
        #expect(name(SketchWindowConfig()) == nil)
        #expect(name(SketchWindowConfig(), env: ["METAPHOR_SYPHON_NAME": "E"]) == nil)
        #expect(name(SketchWindowConfig(), headless: true) == nil, "セカンダリはヘッドレスでも暗黙に publish しない（従来どおり）")
    }

    @Test("makeOutput は名前が決まるときだけ SyphonPlugin を返す")
    @MainActor
    func makeOutput() {
        let provider = SyphonOutputProvider()
        let on = provider.makeOutput(context: MetaphorOutputContext(
            scope: .primary(SketchConfig(title: "T", syphon: true)), environment: [:], isHeadless: false
        ))
        #expect(on is SyphonPlugin)

        let off = provider.makeOutput(context: MetaphorOutputContext(
            scope: .primary(SketchConfig(title: "T")), environment: [:], isHeadless: false
        ))
        #expect(off == nil)
    }
}
