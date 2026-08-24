import Foundation
import Testing
import simd

@testable import MetaphorCore

// MARK: - D-20: Orbit Camera

@Suite("D-20 Orbit Camera")
@MainActor
struct OrbitCameraTests {

    @Test("Default camera position")
    func defaultPosition() {
        let camera = OrbitCamera()
        let eye = camera.eye
        // default: distance=500, azimuth=0, elevation=0.3
        // x = 500 * cos(0.3) * sin(0) = 0
        // y = 500 * sin(0.3) ≈ 147.8
        // z = 500 * cos(0.3) * cos(0) ≈ 477.7
        #expect(abs(eye.x) < 0.01)
        #expect(abs(eye.y - 500 * sin(0.3)) < 0.1)
        #expect(abs(eye.z - 500 * cos(0.3)) < 0.1)
    }

    @Test("Custom initialization")
    func customInit() {
        let camera = OrbitCamera(distance: 100, azimuth: Float.pi / 2, elevation: 0)
        let eye = camera.eye
        // x = 100 * cos(0) * sin(π/2) = 100
        // y = 100 * sin(0) = 0
        // z = 100 * cos(0) * cos(π/2) ≈ 0
        #expect(abs(eye.x - 100) < 0.1)
        #expect(abs(eye.y) < 0.1)
        #expect(abs(eye.z) < 0.1)
    }

    @Test("Mouse drag changes azimuth and elevation")
    func mouseDrag() {
        let camera = OrbitCamera()
        let initialAzimuth = camera.azimuth
        let initialElevation = camera.elevation

        camera.handleMouseDrag(dx: 100, dy: 50)

        // dx → azimuth decreases (negative dx * sensitivity)
        #expect(camera.azimuth != initialAzimuth)
        // dy → elevation increases
        #expect(camera.elevation != initialElevation)
    }

    @Test("Scroll zoom changes distance")
    func scrollZoom() {
        let camera = OrbitCamera()
        let initialDistance = camera.distance

        camera.handleScroll(delta: 10)

        #expect(camera.distance < initialDistance)
    }

    @Test("Elevation clamping")
    func elevationClamping() {
        let camera = OrbitCamera()

        // 大きなドラッグで elevation を限界に
        camera.handleMouseDrag(dx: 0, dy: 10000)
        #expect(camera.elevation <= camera.maxElevation)

        camera.handleMouseDrag(dx: 0, dy: -20000)
        #expect(camera.elevation >= camera.minElevation)
    }

    @Test("Distance clamping")
    func distanceClamping() {
        let camera = OrbitCamera()

        // 大量ズームイン
        for _ in 0..<100 {
            camera.handleScroll(delta: 100)
        }
        #expect(camera.distance >= camera.minDistance)

        // 大量ズームアウト
        for _ in 0..<100 {
            camera.handleScroll(delta: -100)
        }
        #expect(camera.distance <= camera.maxDistance)
    }

    @Test("Reset restores defaults")
    func reset() {
        let camera = OrbitCamera()
        camera.handleMouseDrag(dx: 100, dy: 50)
        camera.handleScroll(delta: 10)

        camera.reset()

        #expect(camera.distance == 500)
        #expect(camera.azimuth == 0)
        #expect(camera.elevation == 0.3)
    }

    @Test("Damping smooths movement")
    func damping() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        camera.handleMouseDrag(dx: 100, dy: 0)
        let initialAzimuth = camera.azimuth

        // ダンピング中は update() で徐々に反映
        camera.update()
        let afterFirstUpdate = camera.azimuth

        #expect(afterFirstUpdate != initialAzimuth)

        // 複数回 update でさらに変化
        camera.update()
        camera.update()
        let afterMultipleUpdates = camera.azimuth

        #expect(afterMultipleUpdates != afterFirstUpdate)
    }

    /// ドラッグの総回転量が `damping` に依存しないことを確かめます（#1099）。
    ///
    /// `damping` が決めるのは「離したあとの余韻の長さ」だけで、
    /// 「ドラッグ 1 ピクセルあたり何ラジアン回るか」は `sensitivity` だけで決まります。
    /// 利得補正が無いと総回転量が `1 / (1 - damping)` 倍に膨らみます。
    @Test(
        "Damping does not change total rotation",
        arguments: [Float(0.5), 0.86, 0.9, 0.95])
    func dampingPreservesTotalRotation(damping: Float) {
        /// 60 フレーム × 10px を水平にドラッグし、余韻が止まるまで回しきった方位角。
        func totalAzimuthChange(damping: Float) -> Float {
            let camera = OrbitCamera()
            camera.damping = damping
            for _ in 0..<60 {
                camera.handleMouseDrag(dx: 10, dy: 0)
                camera.update()
            }
            // update() は速度が十分小さくなるとゼロへ丸めるので、必ず止まる
            for _ in 0..<100_000 {
                let before = camera.azimuth
                camera.update()
                if camera.azimuth == before { break }
            }
            return camera.azimuth
        }

        let undamped = totalAzimuthChange(damping: 0)
        let damped = totalAzimuthChange(damping: damping)

        // sensitivity 0.005 rad/px × 600px = 3.0 rad（dx 正 → 方位角は負へ）
        #expect(abs(undamped + 3.0) < 0.001)
        // 差は速度のゼロ丸め（0.0001 rad/frame）による打ち切り分だけ
        #expect(
            abs(damped - undamped) < 0.01,
            "damping \(damping): \(damped) rad vs undamped \(undamped) rad")
    }

    /// `damping = 1` でもカメラが固まらないことを確かめます（#1099）。
    ///
    /// 利得 `1 - damping` がゼロになると入力が速度へ一切乗らなくなるため、
    /// 内部では 1 未満へ丸めます。代入した値そのものは保たれます。
    @Test("Damping of 1 does not freeze the camera")
    func dampingOneStillRotates() {
        let camera = OrbitCamera()
        camera.damping = 1

        camera.handleMouseDrag(dx: 100, dy: 0)
        camera.update()

        #expect(camera.azimuth != 0)
        #expect(camera.damping == 1)
    }

    @Test("Up vector is (0,1,0)")
    func upVector() {
        let camera = OrbitCamera()
        #expect(camera.up == SIMD3(0, 1, 0))
    }

    @Test("Target offset affects eye position")
    func targetOffset() {
        let camera = OrbitCamera(distance: 100, azimuth: 0, elevation: 0)
        let eye1 = camera.eye

        camera.target = SIMD3(100, 0, 0)
        let eye2 = camera.eye

        #expect(abs(eye2.x - eye1.x - 100) < 0.1)
    }
}

// MARK: - #1100: 押下フレームの座標の飛び

/// 押下が届いたフレームで `orbitControl()` がカメラを回さないことを確かめます（#1100）。
///
/// `orbitControl()` は「押下中か」と「前フレームからの移動量」だけを見ていたため、
/// カーソルが前フレームの位置から離れた場所で押されると、その距離まるごとが
/// 回転として入っていました。押下はドラッグではないので 0 であるべきです。
///
/// `InputManager` の状態と `orbitControl()` の結線が噛み合っているかを見たいので、
/// カメラ単体ではなく実際の `SketchContext` を通します。描画はせず、
/// `MetaphorRenderer.renderFrame()` のフレーム境界（`updateFrame()` → `draw()` 相当
/// → `endFrame()`）だけを手で再現します。
@Suite("D-20 Orbit Camera / press frame (#1100)")
@MainActor
struct OrbitControlPressFrameTests {

    /// 描画を伴わない最小の `SketchContext`。
    private static func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
    }

    /// 1 フレーム進めます。`inFrame` はフレーム頭の後・`draw()` の前に流すイベント
    /// （ヘッドレス注入 = `InputInjectionPlugin.pre()` と同じ位置）。
    private static func frame(
        _ context: SketchContext, inFrame: (InputManager) -> Void = { _ in }
    ) {
        context.input.updateFrame()
        inFrame(context.input)
        context.orbitControl()
        context.input.endFrame()
    }

    @Test("押下だけのフレームは回らない（イベントがフレーム頭の後に届く経路）")
    func pressOnlyFrameDoesNotRotateWithInFrameInjection() throws {
        let context = try Self.makeContext()
        let camera = context.orbitCamera

        // フレーム 1: まだ何も来ていない。カーソルは原点扱い。
        Self.frame(context)
        // フレーム 2: キャンバス中央で 1 回押しただけ。移動は一切していない。
        Self.frame(context) { $0.handleMouseDown(x: 640, y: 400, button: .left) }

        #expect(camera.azimuth == 0, "押下は回転ではない: azimuth \(camera.azimuth) rad")
        #expect(camera.elevation == 0.3, "押下は回転ではない: elevation \(camera.elevation) rad")
    }

    @Test("押下だけのフレームは回らない（イベントがフレーム頭の前に届く経路）")
    func pressOnlyFrameDoesNotRotateWithBetweenFrameEvents() throws {
        let context = try Self.makeContext()
        let camera = context.orbitCamera

        // AppKit はフレームとフレームの間でイベントを処理する。押下の印を
        // updateFrame() で消すと、この経路では draw() が見る前に消えてしまう。
        Self.frame(context)
        context.input.handleMouseDown(x: 640, y: 400, button: .left)
        Self.frame(context)

        #expect(camera.azimuth == 0, "押下は回転ではない: azimuth \(camera.azimuth) rad")
        #expect(camera.elevation == 0.3, "押下は回転ではない: elevation \(camera.elevation) rad")
    }

    @Test("押下フレームの飛びは damping を上げても回転として残らない")
    func pressOnlyFrameDoesNotRotateWithDamping() throws {
        let context = try Self.makeContext()
        let camera = context.orbitCamera
        camera.damping = 0.9

        Self.frame(context)
        Self.frame(context) { $0.handleMouseDown(x: 640, y: 400, button: .left) }
        // 余韻が止まるまで回しきる（#1130 以降、総回転量は damping に依存しない）。
        for _ in 0..<100_000 {
            let before = camera.azimuth
            camera.update()
            if camera.azimuth == before { break }
        }

        #expect(abs(camera.azimuth) < 0.001, "余韻にも乗らない: azimuth \(camera.azimuth) rad")
    }

    @Test("押下と同じフレームに届いたドラッグは押下位置からのぶんだけ回る")
    func dragInThePressFrameRotatesFromThePressPoint() throws {
        let context = try Self.makeContext()
        let camera = context.orbitCamera

        // ライブビューアは溜まったイベントを 1 フレームでまとめて流す。押下ごと
        // 捨てるとドラッグまで落ちるので、押下位置からの 10px だけを回す。
        Self.frame(context)
        Self.frame(context) {
            $0.handleMouseDown(x: 640, y: 400, button: .left)
            $0.handleMouseDragged(x: 650, y: 400)
        }

        #expect(
            abs(camera.azimuth - (-10 * camera.sensitivity)) < 1e-6,
            "押下位置からの 10px 分だけ回る: azimuth \(camera.azimuth) rad")
    }

    @Test("押下の次のフレームは通常どおりドラッグとして回る")
    func frameAfterThePressRotatesNormally() throws {
        let context = try Self.makeContext()
        let camera = context.orbitCamera

        Self.frame(context)
        Self.frame(context) { $0.handleMouseDown(x: 640, y: 400, button: .left) }
        Self.frame(context) { $0.handleMouseDragged(x: 660, y: 400) }

        #expect(
            abs(camera.azimuth - (-20 * camera.sensitivity)) < 1e-6,
            "押下フラグは 1 フレームで消える: azimuth \(camera.azimuth) rad")
    }
}

// MARK: - #1127: 仰角の上下限に当たったときの速度

/// 仰角が上下限に当たったフレームで余韻が捨てられることを確かめます（#1127）。
///
/// `update()` は角度だけを `minElevation` / `maxElevation` へ丸めていて、
/// 速度はそのまま減衰していました。真上まで振り切って手を離すと、
/// 減衰しきるまでカメラが上限を押し続け、逆向きのドラッグは
/// 残った速度を打ち消すまで効きません。
@Suite("D-20 Orbit Camera / elevation limits (#1127)")
@MainActor
struct OrbitCameraElevationLimitTests {

    /// 上限へ振り切ったあと、逆向きの小さなドラッグが 1 フレームで効くこと。
    @Test("上限に当たったあとの逆ドラッグはすぐ効く")
    func reverseDragAfterHittingUpperLimitTakesEffectImmediately() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        // 上限を大きく超えるドラッグ（dy 負 → 仰角は正方向）
        camera.handleMouseDrag(dx: 0, dy: -10_000)
        camera.update()
        #expect(camera.elevation == camera.maxElevation)

        // 手を離してから 10px 下へドラッグし直す
        camera.handleMouseDrag(dx: 0, dy: 10)
        camera.update()

        #expect(
            camera.elevation < camera.maxElevation,
            "上限に押し付けられたまま: elevation \(camera.elevation) rad")
    }

    /// 下限側も同じであること。
    @Test("下限に当たったあとの逆ドラッグはすぐ効く")
    func reverseDragAfterHittingLowerLimitTakesEffectImmediately() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        camera.handleMouseDrag(dx: 0, dy: 10_000)
        camera.update()
        #expect(camera.elevation == camera.minElevation)

        camera.handleMouseDrag(dx: 0, dy: -10)
        camera.update()

        #expect(
            camera.elevation > camera.minElevation,
            "下限に押し付けられたまま: elevation \(camera.elevation) rad")
    }

    /// 上下限のない方位角の余韻は、仰角が壁に当たっても巻き添えで止まらないこと。
    @Test("仰角が限界に当たっても方位角の余韻は続く")
    func azimuthGlideSurvivesAnElevationLimitHit() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        // 斜めに振り切る: 仰角は上限へ、方位角は限界が無いので回り続ける
        camera.handleMouseDrag(dx: 100, dy: -10_000)
        camera.update()
        #expect(camera.elevation == camera.maxElevation)

        let azimuthAfterHit = camera.azimuth
        camera.update()

        #expect(
            camera.azimuth != azimuthAfterHit,
            "方位角の余韻まで止まっている: azimuth \(camera.azimuth) rad")
    }

    /// 限界に当たっていないフレームでは、これまでどおり余韻が続くこと。
    @Test("限界に当たらない仰角の余韻はこれまでどおり続く")
    func elevationGlideContinuesWhenNoLimitIsHit() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        // 上限（≈1.56 rad）に届かない小さなドラッグ
        camera.handleMouseDrag(dx: 0, dy: -10)
        camera.update()
        let afterFirstUpdate = camera.elevation
        camera.update()

        #expect(camera.elevation > afterFirstUpdate)
        #expect(camera.elevation < camera.maxElevation)
    }
}
