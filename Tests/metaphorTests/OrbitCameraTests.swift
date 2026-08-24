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
