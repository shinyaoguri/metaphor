import Foundation
import Testing

@testable import MetaphorCore
@testable import MetaphorTestSupport

/// 変換ファミリの 2D/3D 適用規則（ADR-0005 Decision 1 + Amendment 2026-08-02）を凍結する。
///
/// Amendment 以前、この規範は **doc に書いてあるだけ**でどのテストにも固定されていなかった
/// （Issue #385）。`translate(x, y)` の適用先を変えても既存テストが 1 本も赤くならず、
/// ゴールデンも 1 画素も動かない状態だったため、ここで表そのものを凍結する。
///
/// 規範（Amendment 後）:
///
/// | 適用先 | API |
/// |---|---|
/// | 2D/3D 両方 | `translate(x,y)` / `rotate(a)` / `scale(sx,sy)` / `scale(s)` / `resetMatrix` / スタック系 |
/// | 2D のみ | `shearX` / `shearY` / `applyMatrix(float3x3)` |
/// | 3D のみ | `translate(x,y,z)` / `rotateX/Y/Z` / `scale(x,y,z)` / `applyMatrix(float4x4)` |
@Suite("Transform Semantics (ADR-0005)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TransformSemanticsTests {

    private func makeContext(width: Int = 200, height: Int = 100) throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: width, height: height)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
    }

    // MARK: - 2D/3D 両方に効くもの（Amendment で統一した 3 本）

    @Test("translate(x, y) は 2D と 3D の両方へ z = 0 の平行移動として効く")
    func translateAppliesToBothCanvases() throws {
        let c = try makeContext()
        c.translate(30, 70)

        let t2 = c.canvas.currentTransform
        #expect(t2[2].x == 30)
        #expect(t2[2].y == 70)

        let t3 = c.canvas3D.currentTransform
        #expect(t3.columns.3.x == 30)
        #expect(t3.columns.3.y == 70)
        #expect(t3.columns.3.z == 0, "z は動かさない")
    }

    @Test("rotate(a) は 3D では rotateZ(a) と同じ回転になる")
    func rotateMatchesRotateZOn3D() throws {
        let angle: Float = 0.7
        let viaRotate = try makeContext()
        viaRotate.rotate(angle)

        let viaRotateZ = try makeContext()
        viaRotateZ.rotateZ(angle)

        #expect(viaRotate.canvas3D.currentTransform == viaRotateZ.canvas3D.currentTransform)
        // 2D 側にも効いていること（片肺になっていない）。
        #expect(viaRotate.canvas.currentTransform != float3x3(1))
    }

    @Test("scale(sx, sy) は 3D では z 等倍のスケールになる")
    func nonUniformScaleAppliesToBothCanvases() throws {
        let c = try makeContext()
        c.scale(2, 3)

        let t2 = c.canvas.currentTransform
        #expect(t2[0].x == 2)
        #expect(t2[1].y == 3)

        let t3 = c.canvas3D.currentTransform
        #expect(t3.columns.0.x == 2)
        #expect(t3.columns.1.y == 3)
        #expect(t3.columns.2.z == 1, "z は等倍のまま")
    }

    @Test("scale(s) は 2D・3D とも全軸に効く")
    func uniformScaleAppliesToBothCanvases() throws {
        let c = try makeContext()
        c.scale(2)
        #expect(c.canvas.currentTransform[0].x == 2)
        #expect(c.canvas3D.currentTransform.columns.0.x == 2)
        #expect(c.canvas3D.currentTransform.columns.2.z == 2)
    }

    // MARK: - 2D のみ（統一の対象外）

    @Test("shearX / shearY / applyMatrix(float3x3) は 2D のみに効く")
    func twoDOnlyTransformsDoNotTouch3D() throws {
        for apply in [
            { (c: SketchContext) in c.shearX(0.3) },
            { (c: SketchContext) in c.shearY(0.3) },
            { (c: SketchContext) in c.applyMatrix(float3x3(2)) },
            { (c: SketchContext) in c.applyMatrix(1, 0, 5, 0, 1, 7) },
        ] {
            let c = try makeContext()
            apply(c)
            #expect(c.canvas.currentTransform != float3x3(1), "2D には効く")
            #expect(c.canvas3D.currentTransform == .identity, "3D には効かない")
        }
    }

    // MARK: - 3D のみ

    @Test("translate(x,y,z) / rotateX/Y/Z / scale(x,y,z) / applyMatrix(float4x4) は 3D のみに効く")
    func threeDOnlyTransformsDoNotTouch2D() throws {
        for apply in [
            { (c: SketchContext) in c.translate(1, 2, 3) },
            { (c: SketchContext) in c.rotateX(0.3) },
            { (c: SketchContext) in c.rotateY(0.3) },
            { (c: SketchContext) in c.scale(2, 3, 4) },
            { (c: SketchContext) in c.applyMatrix(float4x4(scale: 2)) },
        ] {
            let c = try makeContext()
            apply(c)
            #expect(c.canvas3D.currentTransform != .identity, "3D には効く")
            #expect(c.canvas.currentTransform == float3x3(1), "2D には効かない")
        }
        // rotateZ だけは 2D の rotate と同義だが、3D 専用 API なので 2D は動かさない。
        let c = try makeContext()
        c.rotateZ(0.3)
        #expect(c.canvas3D.currentTransform != .identity)
        #expect(c.canvas.currentTransform == float3x3(1))
    }

    // MARK: - スタックと座標系

    @Test("pushMatrix / popMatrix で囲めば統一後も 3D へ漏れない")
    func pushMatrixContainsUnifiedTransforms() throws {
        let c = try makeContext()
        let base2D = c.canvas.currentTransform
        let base3D = c.canvas3D.currentTransform

        c.pushMatrix()
        c.translate(100, 100)
        c.rotate(0.3)
        c.scale(2, 3)
        #expect(c.canvas3D.currentTransform != base3D, "囲みの内側では効いている")
        c.popMatrix()

        #expect(c.canvas.currentTransform == base2D)
        #expect(c.canvas3D.currentTransform == base3D)
    }

    /// P3D 統一が成り立つ前提そのもの: 2D と 3D は同じピクセル空間を共有している。
    /// これが崩れると `translate(x, y)` を 3D へ流すこと自体が誤りになる。
    @Test("2D と 3D は同じピクセル空間を共有する（同座標に描くと同じ画素に落ちる）")
    func canvasesShareThePixelSpace() throws {
        let size = 128
        func centroid(_ draw: @escaping (SketchContext) -> Void) throws -> SIMD2<Float> {
            let renderer = try MetaphorRenderer(width: size, height: size)
            let canvas = try Canvas2D(renderer: renderer)
            let canvas3D = try Canvas3D(renderer: renderer)
            let context = SketchContext(
                renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
            )
            canvas.onSetClearColor = { [weak renderer] r, g, b, a in
                renderer?.setClearColor(r, g, b, a)
            }
            renderer.onDraw = { encoder, _ in
                context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
                draw(context)
                context.endFrame()
            }
            renderer.useExternalRenderLoop = true
            renderer.renderFrame()
            let img = try GoldenImage.readback(
                texture: renderer.textureManager.colorTexture,
                commandQueue: renderer.commandQueue
            )
            var sum = SIMD2<Float>.zero
            var n: Float = 0
            for y in 0..<img.height {
                for x in 0..<img.width where img.rgba[(y * img.width + x) * 4] > 40 {
                    sum += SIMD2(Float(x), Float(y))
                    n += 1
                }
            }
            #expect(n > 0, "何も描かれていない")
            return sum / max(n, 1)
        }

        let flat = try centroid { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            c.rect(32 - 8, 24 - 8, 16, 16)
        }
        let solid = try centroid { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            // colorMode 基準（既定 0〜255）で全開。他にライトを足さないので実際には
            // 無照明パス（fill 色をそのまま使う）だが、単位を取り違えた値は残さない。
            c.ambientLight(255)
            c.pushMatrix()
            c.translate(32, 24, 0)
            c.box(16)
            c.popMatrix()
        }
        #expect(abs(flat.x - solid.x) < 3, "x: 2D=\(flat.x) 3D=\(solid.x)")
        #expect(abs(flat.y - solid.y) < 3, "y: 2D=\(flat.y) 3D=\(solid.y)")
    }

    /// Amendment が直した典型パターン（`translate(w/2, h/2)` → 3D 描画）。
    /// 統一前はワールド原点 = ピクセル空間の左上に張り付いて画面外へ切れていた。
    @Test("translate(w/2, h/2) 後の 3D 描画が中央に来る（統一前は左上に張り付いていた）")
    func centeringIdiomMoves3DContent() throws {
        let size = 128
        let renderer = try MetaphorRenderer(width: size, height: size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            context.background(Color(r: 0, g: 0, b: 0))
            context.noStroke()
            context.fill(Color(r: 1, g: 1, b: 1))
            context.ambientLight(255)  // colorMode 基準（既定 0〜255）
            context.translate(64, 32)
            context.box(20)
            context.endFrame()
        }
        renderer.useExternalRenderLoop = true
        renderer.renderFrame()

        let img = try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture,
            commandQueue: renderer.commandQueue
        )
        var sum = SIMD2<Float>.zero
        var n: Float = 0
        for y in 0..<img.height {
            for x in 0..<img.width where img.rgba[(y * img.width + x) * 4] > 40 {
                sum += SIMD2(Float(x), Float(y))
                n += 1
            }
        }
        let centroid = sum / max(n, 1)
        #expect(abs(centroid.x - 64) < 3, "centroid=\(centroid)")
        #expect(abs(centroid.y - 32) < 3, "centroid=\(centroid)")
    }

    // MARK: - modelX / modelY / modelZ の意味論（Issue #814）
    //
    // Processing の `modelX/Y/Z` は `cameraInv * modelview * point`
    // （`modelview = camera * currentMatrix`）でカメラが打ち消し合い、実質
    // `currentMatrix * point` = **ワールド座標**を返す。p5.js の `screenToWorld()`
    // （スクリーン座標 → 3D 空間の逆投影）とは別物で、metaphor は API 名が Processing
    // 語彙であることと ADR-0007 の「Processing 準拠」原則から前者を採る。
    // 下の cameraDoesNotAffectModelPosition が、その判断を固定する検査。

    @Test("modelX/Y/Z は translate の量をそのままワールド座標として返す")
    func modelPositionFollowsTranslate() throws {
        let c = try makeContext()
        c.translate(10, 20, 30)

        let sketch = ModelCoordinateProbeSketch()
        sketch._context = c
        #expect(sketch.modelX(0, 0, 0) == 10)
        #expect(sketch.modelY(0, 0, 0) == 20)
        #expect(sketch.modelZ(0, 0, 0) == 30)
    }

    @Test("変換なし（単位行列）では入力がそのまま返る")
    func modelPositionIsIdentityWithoutTransform() throws {
        let c = try makeContext()
        #expect(c.canvas3D.currentTransform == .identity, "前提: 変換は積まれていない")
        #expect(c.modelPosition(3, -7, 11) == SIMD3<Float>(3, -7, 11))
    }

    @Test("translate → rotate の順で積んだ変換が正しい順序で掛かる")
    func modelPositionAppliesTransformsInOrder() throws {
        let c = try makeContext()
        c.translate(100, 0, 0)
        c.rotateZ(.pi / 2)  // ローカル +x → ワールド +y

        // 掛ける順序を取り違えると x が 100 にならない（回転が平行移動にも掛かる）。
        let p = c.modelPosition(50, 0, 0)
        #expect(abs(p.x - 100) < 1e-4, "p=\(p)")
        #expect(abs(p.y - 50) < 1e-4, "p=\(p)")
        #expect(abs(p.z) < 1e-4, "p=\(p)")

        // 逆回転を積めば元のローカル座標へ戻る（往復）。
        c.rotateZ(-.pi / 2)
        let back = c.modelPosition(50, 0, 0)
        #expect(abs(back.x - 150) < 1e-4, "back=\(back)")
        #expect(abs(back.y) < 1e-4, "back=\(back)")
    }

    @Test("pushMatrix 〜 popMatrix を跨ぐと値が積まれて戻る")
    func modelPositionTracksMatrixStack() throws {
        let c = try makeContext()
        c.translate(10, 0, 0)
        let outside = c.modelPosition(0, 0, 0)

        c.pushMatrix()
        c.translate(0, 25, 0)
        let inside = c.modelPosition(0, 0, 0)
        #expect(inside == SIMD3<Float>(10, 25, 0), "inside=\(inside)")
        #expect(inside != outside, "push の中では値が変わる")

        c.popMatrix()
        #expect(c.modelPosition(0, 0, 0) == outside, "pop で元へ戻る")
    }

    /// **カメラ非依存であること**を固定する検査（Issue #814 の判断の要）。
    ///
    /// Issue 本文は「MVP の `.inverse`」「入力の z にスクリーン深度」と書いていたが、
    /// それは p5.js の `screenToWorld()` の仕様。Processing 準拠に読み替えた結果、
    /// `modelX/Y/Z` はカメラ・投影をまったく通さない。カメラを動かして値が変われば、
    /// 実装が MVP 経路に戻ってしまったということ。
    @Test("camera() を動かしても modelX/Y/Z は変わらない（screenX は変わる）")
    func cameraDoesNotAffectModelPosition() throws {
        let c = try makeContext()
        c.translate(10, 20, 30)

        let before = c.modelPosition(1, 2, 3)
        let screenBefore = c.screenPosition(1, 2, 3)

        c.camera(eye: SIMD3(150, -80, 400), center: SIMD3(20, 10, 0))

        #expect(c.modelPosition(1, 2, 3) == before, "カメラはワールド座標に効かない")
        // カメラ変更が本当に効いていることの裏取り。これが無いと、camera() が
        // no-op になっても上の #expect は通ってしまう。
        #expect(
            c.screenPosition(1, 2, 3) != screenBefore,
            "前提: camera() はスクリーン座標には効いている"
        )
    }

    @Test("Sketch 層の modelX/Y/Z は SketchContext の modelPosition の対応成分と一致する")
    func modelAccessorsMatchModelPosition() throws {
        let c = try makeContext()
        // 3 成分が互いに別値になる非対称な変換にして、取り違えを検出できるようにする。
        c.translate(10, 20, 30)
        c.rotateY(0.6)
        c.scale(1, 2, 3)

        let sketch = ModelCoordinateProbeSketch()
        sketch._context = c

        let p = c.modelPosition(4, 5, 6)
        #expect(sketch.modelX(4, 5, 6) == p.x)
        #expect(sketch.modelY(4, 5, 6) == p.y)
        #expect(sketch.modelZ(4, 5, 6) == p.z)
        #expect(p.x != p.y && p.y != p.z, "3 成分が別値の状況で比較している: \(p)")
    }
}

/// Sketch 層（``Sketch/modelX(_:_:_:)`` など）を呼ぶためだけの最小スケッチ。
/// `_context` を直に差すのは ``SketchRunner`` のセットアップと同じ経路。
@MainActor
private final class ModelCoordinateProbeSketch: Sketch {
    init() {}
}
