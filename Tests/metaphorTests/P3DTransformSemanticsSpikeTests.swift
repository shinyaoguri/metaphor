import Foundation
import Testing

@testable import MetaphorCore
@testable import MetaphorTestSupport

/// 試作（Issue #325 / spike）: 変換ファミリを P3D 意味論へ統一した場合に
/// 「何が変わるか」を数値で固定する検証。判断材料であり、そのまま main へ入れる
/// 想定のテストではない（実装 PR に採用する場合は SketchAPISurfaceTests へ移す）。
@Suite("P3D Transform Semantics (spike)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct P3DTransformSemanticsSpikeTests {

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 200, height: 100)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
    }

    @Test("translate(x, y) は 3D 変換にも z = 0 の平行移動として効く")
    func translate2DAffects3D() throws {
        let c = try makeContext()
        c.translate(30, 70)
        let t = c.canvas3D.currentTransform
        #expect(t.columns.3.x == 30)
        #expect(t.columns.3.y == 70)
        #expect(t.columns.3.z == 0)
    }

    @Test("rotate(a) は 3D 変換に rotateZ(a) と同じ回転として効く")
    func rotate2DAffects3DAsRotateZ() throws {
        let a: Float = 0.7
        let c = try makeContext()
        c.rotate(a)
        let viaRotate = c.canvas3D.currentTransform

        let c2 = try makeContext()
        c2.rotateZ(a)
        #expect(viaRotate == c2.canvas3D.currentTransform)
    }

    @Test("scale(sx, sy) は 3D 変換に z 等倍のスケールとして効く")
    func scale2DAffects3D() throws {
        let c = try makeContext()
        c.scale(2, 3)
        let t = c.canvas3D.currentTransform
        #expect(t.columns.0.x == 2)
        #expect(t.columns.1.y == 3)
        #expect(t.columns.2.z == 1)
    }

    /// 2D 変換と 3D 変換が同じ座標系（ピクセル空間・左上原点・y 下向き）を
    /// 共有していることの確認。P3D 統一が「単位の異なる 2 空間の混線」に
    /// ならない根拠。
    /// 実測メモ（副産物のバグ）: レンダリングは 2D / 3D で一致するが、
    /// `screenPosition(x, y, z)` の戻り値だけ y が上下反転している。
    /// 高さ 100 のキャンバスでモデル y = 35 の点が 65 と返る。
    @Test("screenPosition の 2D / 3D は y が反転している（既知の不一致）")
    func screenPositionYIsFlippedIn3D() throws {
        let c = try makeContext()
        // 既定カメラ（Processing P3D 同型のピクセル空間）は begin() で設定される。
        c.canvas3D.begin(encoder: nil, time: 0)
        c.translate(30, 20)
        let p2 = c.screenPosition(10, 15)
        let p3 = c.screenPosition(10, 15, 0)
        #expect(abs(p2.x - p3.x) < 0.5, "x は一致する: 2D=\(p2.x) 3D=\(p3.x)")
        #expect(abs(p2.y - 35) < 0.5, "2D は素直に 35: \(p2.y)")
        // 100 - 35 = 65。レンダリング（下の重心テスト）とは食い違う。
        #expect(abs(p3.y - 65) < 0.5, "3D は反転して 65: \(p3.y)")
    }

    /// 2D と 3D が実際のレンダリングで同じ画素位置に落ちるかを実測する。
    /// `screenPosition` 同士の比較ではなくフレームバッファの重心で確かめる。
    @Test("2D 矩形と 3D ボックスを同じ座標に置くと同じ画素位置に落ちる")
    func renderedPositionsAgree() throws {
        let size = 128
        func centroid(_ draw: @escaping (SketchContext) -> Void) throws -> (Float, Float) {
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
            var sx: Float = 0, sy: Float = 0, n: Float = 0
            for y in 0..<img.height {
                for x in 0..<img.width {
                    let i = (y * img.width + x) * 4
                    // 背景は黒。塗りのある画素だけを拾う。
                    if img.rgba[i] > 40 || img.rgba[i + 1] > 40 || img.rgba[i + 2] > 40 {
                        sx += Float(x); sy += Float(y); n += 1
                    }
                }
            }
            #expect(n > 0, "何も描かれていない")
            return (sx / max(n, 1), sy / max(n, 1))
        }

        // 上寄り・左寄りの同じ位置（32, 24）に 2D と 3D の図形を置く。
        let c2 = try centroid { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            c.rect(32 - 8, 24 - 8, 16, 16)
        }
        let c3 = try centroid { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            c.ambientLight(1.0)
            c.pushMatrix()
            c.translate(32, 24, 0)
            c.box(16)
            c.popMatrix()
        }
        #expect(abs(c2.0 - c3.0) < 3, "x: 2D=\(c2.0) 3D=\(c3.0)")
        #expect(abs(c2.1 - c3.1) < 3, "y: 2D=\(c2.1) 3D=\(c3.1)")
    }

    /// Examples/Topics/Geometry/Icosahedra 型のパターン
    /// （`translate(width/2, height/2)` で中央寄せしてから 3D を描く）が
    /// 統一の前後でどれだけ動くかを画素で測る。
    @Test("Icosahedra 型パターンの移動量（統一前後の実測）")
    func icosahedraPatternShift() throws {
        let size = 128
        func centroidOfBox(usingUnifiedTranslate unified: Bool) throws -> (Float, Float) {
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
                context.ambientLight(1.0)
                if unified {
                    context.translate(64, 32)      // 統一後: 3D にも効く
                } else {
                    context.canvas.translate(64, 32)  // 統一前: 2D だけ
                }
                context.box(20)
                context.endFrame()
            }
            renderer.useExternalRenderLoop = true
            renderer.renderFrame()
            let img = try GoldenImage.readback(
                texture: renderer.textureManager.colorTexture,
                commandQueue: renderer.commandQueue
            )
            var sx: Float = 0, sy: Float = 0, n: Float = 0
            for y in 0..<img.height {
                for x in 0..<img.width {
                    let i = (y * img.width + x) * 4
                    if img.rgba[i] > 40 { sx += Float(x); sy += Float(y); n += 1 }
                }
            }
            return (sx / max(n, 1), sy / max(n, 1))
        }
        let before = try centroidOfBox(usingUnifiedTranslate: false)
        let after = try centroidOfBox(usingUnifiedTranslate: true)
        print("[spike] icosahedra pattern: before=\(before) after=\(after)")
        // 統一前: 2D 変換は 3D に効かないため、ボックスはワールド原点
        //（= ピクセル空間の左上）に描かれ、大半が画面外へ切れる。重心 ≈ (7, 7)。
        #expect(before.0 < 15 && before.1 < 15, "before=\(before) — 左上に張り付く")
        // 統一後: 作者の意図どおり (64, 32) に来る。
        #expect(abs(after.0 - 64) < 3, "after=\(after)")
        #expect(abs(after.1 - 32) < 3, "after=\(after)")
    }

    /// pushMatrix / popMatrix は既に 2D・3D 双方を保存・復元するため、
    /// 統一後も囲まれた変換は 3D 側へ漏れない。
    @Test("pushMatrix で囲めば統一後も 3D 側へ漏れない")
    func pushMatrixContainsTheLeak() throws {
        let c = try makeContext()
        let base = c.canvas3D.currentTransform
        c.pushMatrix()
        c.translate(100, 100)
        c.rotate(0.3)
        c.popMatrix()
        #expect(c.canvas3D.currentTransform == base)
    }
}
