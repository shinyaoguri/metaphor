import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - ortho() の省略時の範囲 (#777)

/// 引数なしの `ortho()` の既定範囲を固定する。
///
/// 正射影は `proj * view` の順で**ビュー空間**に効くが、Processing 風の既定カメラは
/// キャンバス中央 `(width / 2, height / 2, defaultZ)` からその真正面を見ているので、
/// ビュー空間の原点は画面中央にある。修正前の既定 `[0, width] × [height, 0]` は
/// ワールド座標のつもりの範囲で、原点が範囲の隅に当たるため被写体がちょうど
/// 半画面ぶん隅へ寄っていた。加えて `bottom > top` だったため上下も反転しており
/// （`computeViewProjection()` の Y 反転と二重に効く）、near/far も ±1000 固定で
/// ビュー z が `-defaultZ` を中心に散るぶんを覆えていなかった。
@Suite("ortho() の省略時の範囲", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct OrthoDefaultBoundsTests {

    /// Issue #777 の実測と同じ 1280x720。既定カメラは `begin()` で入る
    /// （構築直後は `(0, 0, 5)` のままなので、必ず 1 フレーム開始しておく）。
    private func makeCanvas() throws -> (MetaphorRenderer, Canvas3D) {
        let renderer = try MetaphorRenderer(width: 1280, height: 720)
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.begin(encoder: nil, time: 0)
        return (renderer, canvas3D)
    }

    @Test("引数なしの ortho() は既定カメラの注視点を画面中央へ写す (regression #777)")
    func defaultBoundsKeepSubjectCentered() throws {
        let (_, canvas3D) = try makeCanvas()
        canvas3D.ortho()

        let center = canvas3D.screenPosition(canvas3D.width / 2, canvas3D.height / 2, 0)
        #expect(abs(center.x - canvas3D.width / 2) < 0.5, "実測 x = \(center.x)")
        #expect(abs(center.y - canvas3D.height / 2) < 0.5, "実測 y = \(center.y)")
    }

    @Test("ortho() の既定範囲はキャンバスの四隅と一致する（境界）")
    func defaultBoundsMatchCanvasCorners() throws {
        let (_, canvas3D) = try makeCanvas()
        canvas3D.ortho()

        let topLeft = canvas3D.screenPosition(0, 0, 0)
        #expect(abs(topLeft.x) < 0.5, "左上の x = \(topLeft.x)")
        #expect(abs(topLeft.y) < 0.5, "左上の y = \(topLeft.y)")

        let bottomRight = canvas3D.screenPosition(canvas3D.width, canvas3D.height, 0)
        #expect(abs(bottomRight.x - canvas3D.width) < 0.5, "右下の x = \(bottomRight.x)")
        #expect(abs(bottomRight.y - canvas3D.height) < 0.5, "右下の y = \(bottomRight.y)")
    }

    @Test("ortho() の既定範囲はワールド 1 単位を 1px に写す")
    func defaultBoundsKeepPixelScale() throws {
        let (_, canvas3D) = try makeCanvas()
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2
        canvas3D.ortho()

        let left = canvas3D.screenPosition(cx - 100, cy, 0)
        let right = canvas3D.screenPosition(cx + 100, cy, 0)
        #expect(abs((right.x - left.x) - 200) < 0.01, "横幅 = \(right.x - left.x)")

        let upper = canvas3D.screenPosition(cx, cy - 80, 0)
        let lower = canvas3D.screenPosition(cx, cy + 80, 0)
        #expect(abs((lower.y - upper.y) - 160) < 0.01, "縦幅 = \(lower.y - upper.y)")

        // 正射影なので奥行きが変わっても寸法は変わらない
        let deep = canvas3D.screenPosition(cx + 100, cy, -600)
        #expect(abs(deep.x - right.x) < 0.01, "奥に置いても x は動かない")
    }

    @Test("ortho() の既定は透視投影・2D と同じ y の向きになる (regression #777)")
    func defaultBoundsMatchPerspectiveYDirection() throws {
        let renderer = try MetaphorRenderer(width: 1280, height: 720)
        let canvas3D = try Canvas3D(renderer: renderer)
        let canvas = try Canvas2D(renderer: renderer)
        canvas3D.begin(encoder: nil, time: 0)
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2

        // 既定（透視投影）の y の向きを基準にする
        let perspectiveShift =
            canvas3D.screenPosition(cx, cy + 80, 0).y - canvas3D.screenPosition(cx, cy - 80, 0).y
        canvas3D.ortho()
        let orthoShift =
            canvas3D.screenPosition(cx, cy + 80, 0).y - canvas3D.screenPosition(cx, cy - 80, 0).y
        #expect(perspectiveShift > 0, "透視投影ではワールド +y が画面下向き")
        #expect(orthoShift > 0, "平行投影でも同じ向きでなければならない: \(orthoShift)")

        // 2D の screenPosition とも一致する（= 2D と同じピクセル座標）
        let flat = canvas.screenPosition(cx, cy + 80)
        let solid = canvas3D.screenPosition(cx, cy + 80, 0)
        #expect(abs(solid.x - flat.x) < 0.5, "2D \(flat.x) / 3D \(solid.x)")
        #expect(abs(solid.y - flat.y) < 0.5, "2D \(flat.y) / 3D \(solid.y)")
    }

    @Test("ortho() の既定 near/far は既定カメラ前後の奥行きを覆う (regression #777)")
    func defaultDepthRangeCoversScene() throws {
        let (_, canvas3D) = try makeCanvas()
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2
        canvas3D.ortho()

        // Issue #777 のコメントで消えた板と同じ深さ（-600）を含む
        for z in [Float(200), 0, -300, -600] {
            let p = canvas3D.screenPosition(cx, cy, z)
            #expect(p.z > 0 && p.z < 1, "z = \(z) が near/far の内側に無い: ndc.z = \(p.z)")
        }

        // 奥ほど深度値が大きい（深度テストの向きが逆転していない）
        let near = canvas3D.screenPosition(cx, cy, 200)
        let far = canvas3D.screenPosition(cx, cy, -600)
        #expect(far.z > near.z, "手前 \(near.z) / 奥 \(far.z)")
    }

    @Test("既定 near/far の外側はクリップされる（境界）")
    func pointsOutsideDefaultDepthRangeAreClipped() throws {
        let (_, canvas3D) = try makeCanvas()
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2
        let camZ = canvas3D.cameraEye.z
        canvas3D.ortho()

        // 可視のビュー z は [-far, -near]。ワールド z = ビュー z + camZ。
        let atFarPlane = -(camZ * 10) + camZ
        let atNearPlane = (camZ * 10) + camZ
        #expect(abs(canvas3D.screenPosition(cx, cy, atFarPlane).z - 1) < 0.001, "far 面はちょうど 1")
        #expect(abs(canvas3D.screenPosition(cx, cy, atNearPlane).z) < 0.001, "near 面はちょうど 0")
        #expect(canvas3D.screenPosition(cx, cy, atFarPlane - 10).z > 1, "far より奥は外れる")
        #expect(canvas3D.screenPosition(cx, cy, atNearPlane + 10).z < 0, "near より手前は外れる")
    }

    @Test("明示した範囲は既定に上書きされない")
    func explicitBoundsAreHonored() throws {
        let (_, canvas3D) = try makeCanvas()
        let cx = canvas3D.width / 2
        let cy = canvas3D.height / 2
        // 修正前の既定と同じ範囲。明示すれば従来どおり隅へ寄る（#777 の症状そのもの）
        canvas3D.ortho(
            left: 0, right: canvas3D.width,
            bottom: canvas3D.height, top: 0,
            near: -1000, far: 1000
        )

        #expect(canvas3D.orthoLeft == 0 && canvas3D.orthoRight == canvas3D.width)
        #expect(canvas3D.orthoBottom == canvas3D.height && canvas3D.orthoTop == 0)
        #expect(canvas3D.nearPlane == -1000 && canvas3D.farPlane == 1000)

        let center = canvas3D.screenPosition(cx, cy, 0)
        #expect(abs(center.x) < 0.5, "左端へ寄る: \(center.x)")
        #expect(abs(center.y - canvas3D.height) < 0.5, "下端へ寄る: \(center.y)")
    }

    @Test("SketchContext / Sketch 経由でも同じ既定が入る (regression #777)")
    func defaultsAgreeAcrossLayers() throws {
        let renderer = try MetaphorRenderer(width: 1280, height: 720)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas3D.begin(encoder: nil, time: 0)

        // Canvas3D 直呼びを基準にする
        canvas3D.ortho()
        let expected = OrthoState(canvas3D)

        canvas3D.begin(encoder: nil, time: 0)
        context.ortho()
        #expect(OrthoState(canvas3D) == expected, "SketchContext の既定が Canvas3D と食い違う")

        let sketch = OrthoProbeSketch()
        sketch._context = context
        canvas3D.begin(encoder: nil, time: 0)
        sketch.ortho()
        #expect(OrthoState(canvas3D) == expected, "Sketch の既定が Canvas3D と食い違う")
    }

    @Test("Graphics3D 経由でも既定の ortho() で被写体が中央に写る (regression #777)")
    func graphics3DDefaultBoundsKeepSubjectCentered() throws {
        let device = MetalTestHelper.device!
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: 400,
            height: 300
        )
        pg3d.beginDraw()
        pg3d.ortho()
        pg3d.fill(Color(r: 1, g: 1, b: 1, alpha: 1))
        pg3d.translate(pg3d.width / 2, pg3d.height / 2, 0)
        pg3d.box(100)
        pg3d.endDraw(wait: true)

        let img = pg3d.toImage()
        img.loadPixels()
        let center = img.get(Int(pg3d.width) / 2, Int(pg3d.height) / 2)
        #expect(
            center.r > 0.01 || center.g > 0.01 || center.b > 0.01,
            "中央が塗られていない: \(center.r), \(center.g), \(center.b)"
        )
    }
}

/// 4 層の既定値を突き合わせるための、`ortho()` が触る状態のスナップショット。
private struct OrthoState: Equatable {
    let left: Float
    let right: Float
    let bottom: Float
    let top: Float
    let near: Float
    let far: Float

    @MainActor
    init(_ canvas3D: Canvas3D) {
        self.left = canvas3D.orthoLeft
        self.right = canvas3D.orthoRight
        self.bottom = canvas3D.orthoBottom
        self.top = canvas3D.orthoTop
        self.near = canvas3D.nearPlane
        self.far = canvas3D.farPlane
    }
}

/// `Sketch` 拡張の `ortho()` を叩くためだけの最小スケッチ。
private final class OrthoProbeSketch: Sketch {
    init() {}
    func setup() {}
    func draw() {}
}
