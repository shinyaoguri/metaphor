import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `drawInstanced(mesh:transforms:)` の意味論を画素で固定する（Issue #442）。
///
/// この API の契約は「`pushMatrix()` / `applyMatrix(t)` / `mesh(m)` / `popMatrix()` の
/// ループと**同値**」。速いことではなく**同じ絵になること**が本体なので、テストは
/// 一貫して「手書きループの結果と完全一致するか」を見る（影オフの即時経路と、
/// 影オンの記録 → 再生経路の両方で）。
@Suite("Canvas3D drawInstanced", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DInstancedTests {

    private static let size = 128

    /// 画面内に散らした 4 インスタンス分のローカル変換。
    private static let transforms: [float4x4] = [
        float4x4(translation: SIMD3(38, 38, 0)),
        float4x4(translation: SIMD3(90, 38, 0)),
        float4x4(translation: SIMD3(38, 90, 0)) * float4x4(rotationY: 0.6),
        float4x4(translation: SIMD3(90, 90, 0)) * float4x4(scale: 1.4),
    ]

    // MARK: - ハーネス

    /// `ShadowLightingTests` と同じ結線でオフスクリーン 1 フレームを描き、全画素を読み戻す。
    ///
    /// - Parameter shadows: true なら記録 → 再生経路（`shouldRecordMainPass`）を通す。
    private func render(
        shadows: Bool = false,
        draw: @escaping (SketchContext, Mesh) -> Void
    ) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        let mesh = try Mesh.box(device: renderer.device, width: 24, height: 24, depth: 24)

        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context, mesh)
            context.endFrame()
        }
        renderer.onAfterDraw = { commandBuffer in
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
        renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
        renderer.onRecordFrame = { _ in
            context.beginRecordingFrame(time: 0, deltaTime: 0)
            draw(context, mesh)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, _ in
            context.replayDeferredMain(encoder: encoder, time: 0)
        }
        renderer.useExternalRenderLoop = true
        if shadows { context.enableShadows(resolution: 512) }
        renderer.renderFrame()
        return try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture, commandQueue: renderer.commandQueue)
    }

    /// `setupScene` が設定する既定の fill 色（`colors` 不足分の期待値）。
    private static let baseFill = Color(r: 0.9, g: 0.9, b: 0.9)

    /// 白 fill・ライトありの共通シーン設定。
    private func setupScene(_ c: SketchContext) {
        c.background(Color(r: 0, g: 0, b: 0))
        c.noStroke()
        c.ambientLight(60)
        c.directionalLight(-0.3, 0.8, -0.5)
        c.fill(Self.baseFill)
    }

    /// 手書きループ版（契約の基準となる書き方）。
    /// `colors` の不足分は `drawInstanced` と同じく「呼び出し時点の fill 色」に戻す。
    private func drawByLoop(_ c: SketchContext, _ mesh: Mesh, colors: [Color]? = nil) {
        for (i, t) in Self.transforms.enumerated() {
            if let colors { c.fill(i < colors.count ? colors[i] : Self.baseFill) }
            c.pushMatrix()
            c.applyMatrix(t)
            c.mesh(mesh)
            c.popMatrix()
        }
    }

    /// 非黒画素の個数を数えます。
    private func nonBlackCount(_ image: GoldenImage) -> Int {
        var count = 0
        for i in stride(from: 0, to: image.rgba.count, by: 4) {
            if image.rgba[i] > 8 || image.rgba[i + 1] > 8 || image.rgba[i + 2] > 8 { count += 1 }
        }
        return count
    }

    /// 「赤が優勢」「緑が優勢」な画素の個数と平均 x を数えます（陰影があっても色相で判定）。
    private func scanHues(_ image: GoldenImage)
        -> (red: Int, green: Int, redMeanX: Float, greenMeanX: Float) {
        var red = 0, green = 0, redSumX = 0, greenSumX = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4  // RGBA
                let r = Int(image.rgba[i]), g = Int(image.rgba[i + 1]), b = Int(image.rgba[i + 2])
                if r > 40 && r > g * 2 && r > b * 2 { red += 1; redSumX += x }
                if g > 40 && g > r * 2 && g > b * 2 { green += 1; greenSumX += x }
            }
        }
        return (red, green,
                red > 0 ? Float(redSumX) / Float(red) : 0,
                green > 0 ? Float(greenSumX) / Float(green) : 0)
    }

    // MARK: - 手書きループとの同値性

    @Test("drawInstanced は push/applyMatrix/mesh/pop のループと同一画素（即時経路）")
    func matchesManualLoopImmediate() throws {
        let loop = try render { c, mesh in
            setupScene(c)
            drawByLoop(c, mesh)
        }
        let instanced = try render { c, mesh in
            setupScene(c)
            c.drawInstanced(mesh, transforms: Self.transforms)
        }

        #expect(nonBlackCount(loop) > 100, "基準側が何も描けていない（nonBlack=\(nonBlackCount(loop))）")
        let comparison = instanced.compare(to: loop)
        #expect(comparison.isIdentical, "手書きループと不一致: \(comparison.summary)")
    }

    @Test("drawInstanced は記録 → 再生経路（影オン）でもループと同一画素")
    func matchesManualLoopRecorded() throws {
        let loop = try render(shadows: true) { c, mesh in
            setupScene(c)
            drawByLoop(c, mesh)
        }
        let instanced = try render(shadows: true) { c, mesh in
            setupScene(c)
            c.drawInstanced(mesh, transforms: Self.transforms)
        }

        #expect(nonBlackCount(loop) > 100, "基準側が何も描けていない（nonBlack=\(nonBlackCount(loop))）")
        let comparison = instanced.compare(to: loop)
        #expect(comparison.isIdentical, "影オンで手書きループと不一致: \(comparison.summary)")
    }

    @Test("直前に別バッチがあってもインスタンスは全部描かれる（キー不一致のフラッシュ）")
    func flushesPrecedingBatch() throws {
        // 別メッシュ（= 別バッチキー）を先に描いてから drawInstanced する。
        // バッチが割れても両方描かれることを、手書きループとの一致で確かめる
        let device = MetalTestHelper.device!
        let other = try Mesh.sphere(device: device, radius: 14)

        let loop = try render { c, mesh in
            setupScene(c)
            c.pushMatrix(); c.translate(64, 64, 0); c.mesh(other); c.popMatrix()
            drawByLoop(c, mesh)
        }
        let instanced = try render { c, mesh in
            setupScene(c)
            c.pushMatrix(); c.translate(64, 64, 0); c.mesh(other); c.popMatrix()
            c.drawInstanced(mesh, transforms: Self.transforms)
        }

        let comparison = instanced.compare(to: loop)
        #expect(comparison.isIdentical, "別バッチを挟むと不一致: \(comparison.summary)")
    }

    @Test("現在の変換行列に積まれる（translate 済みの原点から相対に置かれる）")
    func composesWithCurrentTransform() throws {
        let loop = try render { c, mesh in
            setupScene(c)
            c.pushMatrix()
            c.translate(20, 10, 0)
            drawByLoop(c, mesh)
            c.popMatrix()
        }
        let instanced = try render { c, mesh in
            setupScene(c)
            c.pushMatrix()
            c.translate(20, 10, 0)
            c.drawInstanced(mesh, transforms: Self.transforms)
            c.popMatrix()
        }

        let comparison = instanced.compare(to: loop)
        #expect(comparison.isIdentical, "currentTransform との合成が不一致: \(comparison.summary)")
    }

    // MARK: - インスタンスごとの色

    @Test("colors はインスタンスごとの fill 色になる")
    func perInstanceColors() throws {
        // 左に赤・右に緑を置き、色相と平均 x で「どちらがどちらか」まで見る
        let left = float4x4(translation: SIMD3(38, 64, 0))
        let right = float4x4(translation: SIMD3(90, 64, 0))

        let image = try render { c, mesh in
            setupScene(c)
            c.drawInstanced(mesh, transforms: [left, right],
                            colors: [Color(r: 1, g: 0, b: 0), Color(r: 0, g: 1, b: 0)])
        }

        let scan = scanHues(image)
        #expect(scan.red > 50, "1 つ目のインスタンスが赤で塗られていない（red=\(scan.red)）")
        #expect(scan.green > 50, "2 つ目のインスタンスが緑で塗られていない（green=\(scan.green)）")
        #expect(scan.redMeanX < scan.greenMeanX,
                "色がインスタンスと対応していない（redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX)）")
    }

    @Test("colors が transforms より短いとき、不足分は現在の fill 色になる")
    func shortColorsFallBackToFill() throws {
        let left = float4x4(translation: SIMD3(38, 64, 0))
        let right = float4x4(translation: SIMD3(90, 64, 0))

        let image = try render { c, mesh in
            setupScene(c)
            c.fill(Color(r: 0, g: 1, b: 0))                       // 不足分に使われる色
            c.drawInstanced(mesh, transforms: [left, right],
                            colors: [Color(r: 1, g: 0, b: 0)])    // 1 つ分しか無い
        }

        let scan = scanHues(image)
        #expect(scan.red > 50, "colors[0] が効いていない（red=\(scan.red)）")
        #expect(scan.green > 50, "不足分が現在の fill 色になっていない（green=\(scan.green)）")
        #expect(scan.redMeanX < scan.greenMeanX,
                "不足分が別のインスタンスに割り当たっている（redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX)）")
    }

    @Test("colors が transforms より長いとき、余りは無視される")
    func extraColorsAreIgnored() throws {
        let only = [float4x4(translation: SIMD3(64, 64, 0))]
        let expected = try render { c, mesh in
            setupScene(c)
            c.drawInstanced(mesh, transforms: only, colors: [Color(r: 1, g: 0, b: 0)])
        }
        let withExtras = try render { c, mesh in
            setupScene(c)
            c.drawInstanced(mesh, transforms: only,
                            colors: [Color(r: 1, g: 0, b: 0), Color(r: 0, g: 1, b: 0),
                                     Color(r: 0, g: 0, b: 1)])
        }

        let comparison = withExtras.compare(to: expected)
        #expect(comparison.isIdentical, "余った colors が描画に影響している: \(comparison.summary)")
        #expect(scanHues(withExtras).green == 0, "余った色が描かれている")
    }

    @Test("stroke だけのインスタンスもループと一致する")
    func strokeOnlyMatchesLoop() throws {
        let loop = try render { c, mesh in
            setupScene(c)
            c.noFill()
            c.stroke(Color(r: 1, g: 1, b: 1))
            drawByLoop(c, mesh)
        }
        let instanced = try render { c, mesh in
            setupScene(c)
            c.noFill()
            c.stroke(Color(r: 1, g: 1, b: 1))
            c.drawInstanced(mesh, transforms: Self.transforms)
        }

        #expect(nonBlackCount(loop) > 50, "基準側に stroke が出ていない（nonBlack=\(nonBlackCount(loop))）")
        #expect(instanced.compare(to: loop).isIdentical,
                "stroke 経路で不一致: \(instanced.compare(to: loop).summary)")
    }

    // MARK: - カスタム頂点シェーダー（イミディエイトへのフォールバック）

    /// 頂点カラーをそのまま出す最小のカスタム頂点 + フラグメントシェーダー。
    private static let customShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(BuiltinShaders.canvas3DStructs)

    struct InstancedTestVertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float4 color    [[attribute(2)]];
    };

    struct InstancedTestVertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float4 color;
    };

    vertex InstancedTestVertexOut instancedTestVertex(
        InstancedTestVertexIn in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]]
    ) {
        InstancedTestVertexOut out;
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
        out.color = in.color * uniforms.color;
        return out;
    }

    fragment float4 instancedTestFragment(
        InstancedTestVertexOut in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]]
    ) {
        return in.color;
    }
    """

    @Test("カスタム頂点シェーダーではイミディエイトに落ちても全インスタンスが描かれる")
    func customVertexShaderFallbackMatchesLoop() throws {
        // 末尾の「基準の箱」は、フォールバック経路が currentTransform / fillColor を
        // 戻し忘れたときに位置や色がずれて差分になる（状態リークの検出を兼ねる）
        func scene(_ c: SketchContext, _ mesh: Mesh, instanced: Bool) {
            setupScene(c)
            let material = try? c.createMaterial(
                source: Self.customShaderSource,
                fragmentFunction: "instancedTestFragment",
                vertexFunction: "instancedTestVertex")
            guard let material else {
                Issue.record("カスタムマテリアルを作れなかった")
                return
            }
            c.material(material)
            if instanced {
                c.drawInstanced(mesh, transforms: Self.transforms,
                                colors: [Color(r: 1, g: 0, b: 0), Color(r: 0, g: 1, b: 0)])
            } else {
                drawByLoop(c, mesh, colors: [Color(r: 1, g: 0, b: 0), Color(r: 0, g: 1, b: 0)])
            }
            c.noMaterial()
            c.fill(Color(r: 0.5, g: 0.5, b: 1))
            c.pushMatrix(); c.translate(64, 12, 0); c.mesh(mesh); c.popMatrix()
        }

        let loop = try render { c, mesh in scene(c, mesh, instanced: false) }
        let instanced = try render { c, mesh in scene(c, mesh, instanced: true) }

        #expect(nonBlackCount(loop) > 100, "基準側が何も描けていない（nonBlack=\(nonBlackCount(loop))）")
        #expect(instanced.compare(to: loop).isIdentical,
                "カスタム頂点シェーダー経路で不一致: \(instanced.compare(to: loop).summary)")
    }
}

/// 記録経路（`shouldRecordMainPass`）での `drawInstanced` の内部契約を直接見る（Issue #442）。
///
/// 画素からは見えないが後段の順序保証に効く 2 点 —「N インスタンスが**ひとつの描画呼び出し**
/// として 1 seq / 1 スナップショットを共有すること」「呼び出しが描画状態を汚さないこと」— を、
/// `recordedDrawCalls` と `Canvas3D` の状態で固定する。
@Suite("Canvas3D drawInstanced recording", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DInstancedRecordingTests {

    private static let transforms: [float4x4] = [
        float4x4(translation: SIMD3(10, 0, 0)),
        float4x4(translation: SIMD3(20, 0, 0)),
        float4x4(translation: SIMD3(30, 0, 0)),
    ]

    /// エンコーダ無しで記録だけを行う Canvas3D（`METAPHOR_COMMAND_RECORD` 相当）。
    private func recordingCanvas() throws -> (canvas3D: Canvas3D, mesh: Mesh) {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas3D = try Canvas3D(renderer: renderer)
        let mesh = try Mesh.box(device: renderer.device, width: 10, height: 10, depth: 10)
        canvas3D.commandRecordEnabled = true
        var seq: UInt32 = 0
        canvas3D.seqProvider = { seq += 1; return seq }
        canvas3D.begin(encoder: nil, time: 0)
        return (canvas3D, mesh)
    }

    @Test("N インスタンスは 1 つの seq と 1 つのスナップショットを共有する")
    func sharesSeqAndSnapshot() throws {
        let (canvas3D, mesh) = try recordingCanvas()
        canvas3D.mesh(mesh)                                          // 先行する通常描画（seq=1）
        canvas3D.drawInstanced(mesh, transforms: Self.transforms)    // ここは全部 seq=2

        let calls = canvas3D.recordedDrawCalls
        #expect(calls.count == 1 + Self.transforms.count,
                "インスタンス数だけ記録されていない（count=\(calls.count)）")

        let instanced = Array(calls.dropFirst())
        let seqs = Set(instanced.map(\.seq))
        #expect(seqs.count == 1, "1 回の呼び出しなのに seq が割れている（seqs=\(seqs)）")
        #expect(seqs.first != calls[0].seq, "先行する描画と seq が混ざっている")

        let snapshots = instanced.map(\.stateSnapshot)
        #expect(snapshots.allSatisfy { $0 != nil && $0 === snapshots[0] },
                "スナップショットがインスタンス間で共有されていない")
    }

    @Test("記録される transform は 現在の変換行列 × transforms[i]")
    func recordsComposedTransform() throws {
        let (canvas3D, mesh) = try recordingCanvas()
        canvas3D.translate(5, 7, 0)
        let base = canvas3D.currentTransform
        canvas3D.drawInstanced(mesh, transforms: Self.transforms)

        let calls = canvas3D.recordedDrawCalls
        #expect(calls.count == Self.transforms.count)
        for (i, call) in calls.enumerated() {
            #expect(call.transform == base * Self.transforms[i],
                    "インスタンス \(i) の変換が currentTransform と合成されていない")
        }
    }

    @Test("記録される fill 色は colors、不足分は現在の fill 色")
    func recordsPerInstanceColors() throws {
        let (canvas3D, mesh) = try recordingCanvas()
        canvas3D.fillColor = SIMD4(0, 0, 1, 1)
        canvas3D.drawInstanced(mesh, transforms: Self.transforms,
                               colors: [Color(r: 1, g: 0, b: 0), Color(r: 0, g: 1, b: 0)])

        let colors = canvas3D.recordedDrawCalls.map(\.fillColor)
        #expect(colors == [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 1)],
                "colors の割り当てが違う（colors=\(colors)）")
    }

    @Test("空の transforms・noFill + noStroke は 1 件も記録しない")
    func degenerateCasesRecordNothing() throws {
        let (canvas3D, mesh) = try recordingCanvas()
        canvas3D.drawInstanced(mesh, transforms: [])
        #expect(canvas3D.recordedDrawCalls.isEmpty, "空の transforms が記録されている")

        canvas3D.noFill()
        canvas3D.noStroke()
        canvas3D.drawInstanced(mesh, transforms: Self.transforms)
        #expect(canvas3D.recordedDrawCalls.isEmpty, "noFill + noStroke が記録されている")
    }

    @Test("drawInstanced は変換行列と fill 色を呼び出し前の値に残す")
    func doesNotLeakDrawingState() throws {
        let (canvas3D, mesh) = try recordingCanvas()
        canvas3D.translate(5, 7, 0)
        canvas3D.fillColor = SIMD4(0, 0, 1, 1)
        let base = canvas3D.currentTransform
        let fill = canvas3D.fillColor

        canvas3D.drawInstanced(mesh, transforms: Self.transforms,
                               colors: [Color(r: 1, g: 0, b: 0)])

        #expect(canvas3D.currentTransform == base, "currentTransform が汚れている")
        #expect(canvas3D.fillColor == fill, "fillColor が汚れている")
    }
}
