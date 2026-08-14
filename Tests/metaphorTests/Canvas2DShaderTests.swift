import Metal
import Testing
import simd

@testable import MetaphorCore

/// 2D カスタムフラグメントシェーダ（#647 / Epic #291 E2）のテスト。
///
/// E1（#646）で「記録時にパイプラインキーが確定し、再生は ``Canvas2DPipelineStore`` を
/// 引くだけ」になった性質の上に E2 が載る。ここではその性質を壊していないこと
/// （シェーダ識別子とパラメータが記録側で焼き込まれること）と、Issue で決めた規約
/// （difference / exclusion のフォールバック、前文の自動補完）を固定する。
@Suite("Canvas2D/Shader", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DShaderTests {

    // MARK: - フィクスチャ

    /// 前文（stdlib + 2D 構造体）を持たないソース。`createShader` が補完してくれる前提。
    private static let bareSource = """
    fragment float4 testFragment(Canvas2DVertexOut in [[stage_in]],
                                 constant Canvas2DShaderUniforms &u [[buffer(3)]]) {
        float2 uv = in.position.xy / u.resolution;
        return float4(uv, u.time, 1.0);
    }
    """

    /// stdlib を自分で include したソース。前文が重ねて足されても壊れないことを見る。
    private static let redundantIncludeSource = """
    #include <metal_stdlib>
    using namespace metal;

    fragment float4 redundantFragment(Canvas2DVertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// 前文の有無を「コメントに `#include <metal_stdlib>` と書いてあるか」で判定していた頃、
    /// このソースは前文を足してもらえずコンパイルに落ちていた（#647 の実装中に踏んだ）。
    private static let sourceMentioningStdlibInComment = """
    // #include <metal_stdlib> は書かなくてよい（metaphor が足す）
    fragment float4 commentFragment(Canvas2DVertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    private struct TestParams {
        var amount: Float
    }

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    /// 遅延（記録）モードの Context。encoder 無しでコマンドだけを集める。
    private func makeRecordingContext() throws -> SketchContext {
        let context = try makeContext()
        context.canvas.isDeferring = true
        context.canvas.begin(encoder: nil)
        return context
    }

    private func recordedKeys(_ canvas: Canvas2D) -> [Canvas2DPipelineKey] {
        canvas.deferred2DCommands.compactMap { Self.pipelineKey(of: $0.command) }
    }

    private func recordedShaderParams(_ canvas: Canvas2D) -> [[UInt8]?] {
        canvas.deferred2DCommands.compactMap { slot -> [UInt8]?? in
            switch slot.command {
            case .colorBatch(_, _, _, let params): return .some(params)
            case .texturedBatch(_, _, _, _, let params): return .some(params)
            case .instancedBatch(_, _, _, _, _, let params): return .some(params)
            case .massiveCircles(_, _, _, _, _, let params): return .some(params)
            case .setScissor: return nil
            }
        }
    }

    private static func pipelineKey(of command: Deferred2DCommand) -> Canvas2DPipelineKey? {
        switch command {
        case .colorBatch(let key, _, _, _): return key
        case .texturedBatch(let key, _, _, _, _): return key
        case .instancedBatch(let key, _, _, _, _, _): return key
        case .massiveCircles(let key, _, _, _, _, _): return key
        case .setScissor: return nil
        }
    }

    // MARK: - 読み込みの失敗系

    @Test("存在しないフラグメント関数名は shaderNotFound を投げる")
    func missingFunctionThrows() throws {
        let context = try makeContext()
        do {
            _ = try context.createShader(source: Self.bareSource, fragment: "noSuchFragment")
            Issue.record("存在しない関数名は throw されるべき")
        } catch let error as MetaphorError {
            guard case .material(.shaderNotFound(let name)) = error else {
                Issue.record("shaderNotFound を期待したが \(error)")
                return
            }
            #expect(name == "noSuchFragment")
        }
    }

    @Test("コンパイルできない MSL は shaderCompilationFailed を投げる")
    func brokenSourceThrows() throws {
        let context = try makeContext()
        let broken = """
        fragment float4 brokenFragment(Canvas2DVertexOut in [[stage_in]]) {
            return this_symbol_does_not_exist;
        }
        """
        do {
            _ = try context.createShader(source: broken, fragment: "brokenFragment")
            Issue.record("コンパイルエラーは throw されるべき")
        } catch let error as MetaphorError {
            guard case .shaderCompilationFailed = error else {
                Issue.record("shaderCompilationFailed を期待したが \(error)")
                return
            }
        }
    }

    @Test("パスが読めない loadShader は shaderSourceLoadFailed を投げる")
    func missingFileThrows() throws {
        let context = try makeContext()
        do {
            _ = try context.loadShader("/no/such/shader.metal", fragment: "testFragment")
            Issue.record("読めないパスは throw されるべき")
        } catch let error as MetaphorError {
            guard case .shaderSourceLoadFailed = error else {
                Issue.record("shaderSourceLoadFailed を期待したが \(error)")
                return
            }
        }
    }

    // MARK: - 前文の自動補完

    @Test("前文の無いソースは stdlib と 2D 構造体を補って通る")
    func bareSourceGetsPreamble() throws {
        let context = try makeContext()
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")
        #expect(shader.fragmentFunctionName == "testFragment")
        #expect(Shader2DSource.complete(Self.bareSource).contains("metal_stdlib"))
    }

    @Test("stdlib を自分でも include したソースは二重でも壊れない")
    func redundantIncludeStillCompiles() throws {
        let context = try makeContext()
        let shader = try context.createShader(
            source: Self.redundantIncludeSource, fragment: "redundantFragment")
        #expect(shader.fragmentFunctionName == "redundantFragment")
    }

    @Test("コメントに metal_stdlib と書いてあっても前文は足される")
    func commentDoesNotSuppressPreamble() throws {
        let context = try makeContext()
        // 前文を「ソースに metal_stdlib があるか」で条件分岐していた頃はここで落ちた。
        let shader = try context.createShader(
            source: Self.sourceMentioningStdlibInComment, fragment: "commentFragment")
        #expect(shader.fragmentFunctionName == "commentFragment")
    }

    // MARK: - 記録内容

    @Test("shader() 適用中のバッチはキーにシェーダを持ち、resetShader() で外れる")
    func shaderIsRecordedInPipelineKey() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")

        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))
        canvas.shader(shader)
        canvas.rect(0, 0, 8, 8)
        canvas.resetShader()
        canvas.rect(8, 8, 8, 8)
        canvas.flush()

        let keys = recordedKeys(canvas)
        #expect(keys.count == 2, "shader() / resetShader() でバッチが割れるべき: \(keys)")
        #expect(keys.first?.shader == shader.id)
        #expect(keys.last?.shader == nil)
    }

    @Test("シェーダ適用中の difference は alpha へ正規化される")
    func framebufferFetchBlendFallsBackToAlpha() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")

        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))
        canvas.blendMode(.difference)
        canvas.shader(shader)
        canvas.rect(0, 0, 8, 8)
        canvas.flush()

        let keys = recordedKeys(canvas)
        #expect(keys.count == 1, "\(keys)")
        // difference はフレームバッファフェッチ用の組み込みフラグメントで実装されており
        // カスタムフラグメントと排他。記録時に alpha へ落ちていることを固定する。
        #expect(keys.first?.blend == .alpha)
        #expect(keys.first?.shader == shader.id)
    }

    @Test("シェーダを適用しなければ difference はそのまま残る")
    func framebufferFetchBlendSurvivesWithoutShader() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas

        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))
        canvas.blendMode(.difference)
        canvas.rect(0, 0, 8, 8)
        canvas.flush()

        #expect(recordedKeys(canvas).map(\.blend) == [.difference])
    }

    @Test("setParameters の値は記録時に焼き込まれ、あとから変えても揺れない")
    func parametersAreFrozenAtRecordTime() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")

        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))

        shader.setParameters(TestParams(amount: 0.25))
        canvas.shader(shader)
        canvas.rect(0, 0, 8, 8)

        // shader() を呼び直すとバッチ境界ができ、2 本目は新しい値を持つ。
        shader.setParameters(TestParams(amount: 0.75))
        canvas.shader(shader)
        canvas.rect(8, 8, 8, 8)
        canvas.flush()

        // 記録後にさらに変えても、記録済みコマンドは影響を受けない。
        shader.setParameters(TestParams(amount: 999))

        #expect(recordedAmounts(canvas) == [0.25, 0.75], "\(recordedAmounts(canvas))")
    }

    /// 記録済みコマンドから ``TestParams/amount`` を読み出します。
    private func recordedAmounts(_ canvas: Canvas2D) -> [Float?] {
        recordedShaderParams(canvas).map { params -> Float? in
            guard let bytes = params, bytes.count == MemoryLayout<TestParams>.size else { return nil }
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: TestParams.self).amount }
        }
    }

    @Test("shader() のあとに setParameters を書く順序でも図形ごとの値になる")
    func parametersFollowP5CallOrder() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")

        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))

        // p5 の `shader(s); s.setUniform(...); rect()` と同じ並び。
        canvas.shader(shader)
        shader.setParameters(TestParams(amount: 0.25))
        canvas.rect(0, 0, 8, 8)

        canvas.shader(shader)
        shader.setParameters(TestParams(amount: 0.75))
        canvas.rect(8, 8, 8, 8)
        canvas.flush()

        #expect(recordedAmounts(canvas) == [0.25, 0.75], "\(recordedAmounts(canvas))")
    }

    @Test("シェーダ未適用のバッチは shaderParams を持たない")
    func builtinBatchesCarryNoParams() throws {
        let context = try makeRecordingContext()
        let canvas = context.canvas
        canvas.noStroke()
        canvas.fill(Color(r: 1, g: 1, b: 1))
        canvas.rect(0, 0, 8, 8)
        canvas.flush()

        #expect(recordedShaderParams(canvas).allSatisfy { $0 == nil })
    }

    // MARK: - パイプライン解決

    @Test("カラー系の 3 経路すべてでカスタムパイプラインが解決できる")
    func customPipelineResolvesForColorFamily() throws {
        let context = try makeContext()
        let canvas = context.canvas
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")
        canvas.pipelineStore.register(shader)

        // color / instanced / massive の頂点出力は position + color で同一なので、
        // 1 本のフラグメント関数がそのまま 3 経路に載る（rect() は instanced 経路を通る）。
        for kind in [Canvas2DPipelineKind.color, .instanced, .massiveCircle] {
            let key = Canvas2DPipelineKey(kind, .alpha, shader: shader.id)
            #expect(canvas.pipelineStore.state(for: key) != nil, "\(kind) で解決できるべき")
        }
    }

    @Test("パイプラインを作れないシェーダは組み込みへフォールバックし、描画を落とさない")
    func unbuildableShaderFallsBackToBuiltin() throws {
        let context = try makeContext()
        let canvas = context.canvas
        // texCoord を要求する関数はカラー系の頂点出力と合わず、パイプライン生成が失敗する。
        let textured = try context.createShader(source: """
            fragment float4 texturedOnlyFragment(Canvas2DTexVertexOut in [[stage_in]]) {
                return float4(in.texCoord, 0.0, 1.0);
            }
            """, fragment: "texturedOnlyFragment")
        canvas.pipelineStore.register(textured)

        let key = Canvas2DPipelineKey(.color, .alpha, shader: textured.id)
        let fallback = canvas.pipelineStore.state(for: key)
        #expect(fallback != nil, "組み込みへフォールバックして描画を落とさないこと")
        #expect(fallback === canvas.pipelineStore.state(for: Canvas2DPipelineKey(.color, .alpha)))
    }

    @Test("reload で revision が進み、別のパイプラインキーになる")
    func reloadBumpsRevision() throws {
        let context = try makeContext()
        let shader = try context.createShader(source: Self.bareSource, fragment: "testFragment")
        let before = shader.id
        try shader.reload(shaderLibrary: context.renderer.shaderLibrary)
        #expect(shader.id != before, "ホットリロード後は古いパイプラインを引き当てないこと")
    }
}
