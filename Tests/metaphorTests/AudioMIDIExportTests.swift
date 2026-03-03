import Testing
import Foundation
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - D-19: GIF Export

@Suite("D-19 GIF Exporter")
@MainActor
struct GIFExporterTests {

    @Test("GIFExporter recording state")
    func recordingState() {
        let exporter = GIFExporter()
        #expect(exporter.isRecording == false)
        #expect(exporter.frameCount == 0)

        exporter.beginRecord(fps: 10)
        #expect(exporter.isRecording == true)
    }

    @Test("GIFExporter endRecord with no frames throws")
    func noFramesThrows() {
        let exporter = GIFExporter()
        exporter.beginRecord(fps: 10)
        #expect(throws: GIFExporterError.self) {
            try exporter.endRecord(to: NSTemporaryDirectory() + "empty.gif")
        }
    }

    @Test("GIFExporter loopCount default")
    func loopCountDefault() {
        let exporter = GIFExporter()
        #expect(exporter.loopCount == 0)  // infinite loop
    }

    @Test("GIFExporterError descriptions")
    func errorDescriptions() {
        #expect(GIFExporterError.noFrames.errorDescription?.contains("No frames") == true)
        #expect(GIFExporterError.destinationCreationFailed.errorDescription?.contains("destination") == true)
        #expect(GIFExporterError.finalizationFailed.errorDescription?.contains("finalize") == true)
    }
}

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
