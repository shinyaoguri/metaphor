import Testing
import Foundation
import simd
import Metal
import ImageIO
@testable import metaphor
@testable import MetaphorCore
@testable import MetaphorTestSupport

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
        #expect(throws: MetaphorError.self) {
            try exporter.endRecord(to: NSTemporaryDirectory() + "empty.gif")
        }
    }

    @Test("GIFExporter loopCount default")
    func loopCountDefault() {
        let exporter = GIFExporter()
        #expect(exporter.loopCount == 0)  // infinite loop
    }

    @Test("MetaphorError.export descriptions")
    func errorDescriptions() {
        #expect(MetaphorError.export(.noFrames).errorDescription?.contains("frames") == true)
        #expect(MetaphorError.export(.destinationCreationFailed).errorDescription?.contains("destination") == true)
        #expect(MetaphorError.export(.finalizationFailed).errorDescription?.contains("finalize") == true)
    }

    /// 実フレームを ringSize 超えてキャプチャし、in-flight backpressure と
    /// 順序保証 + ファイナライズが正しく動作することを検証する。
    @Test("end-to-end capture with backpressure", .enabled(if: MetalTestHelper.isGPUAvailable))
    func endToEndCapture() throws {
        guard let device = MetalTestHelper.device,
              let queue = device.makeCommandQueue() else { return }

        // 各フレームを単色で塗ったテクスチャを 8 枚（リングサイズ 3 を超える）
        let width = 32
        let height = 32
        let frameColors: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255),
            (255, 255, 0), (0, 255, 255), (255, 0, 255),
            (128, 128, 128), (255, 255, 255)
        ]

        let exporter = GIFExporter()
        exporter.beginRecord(fps: 10, width: width, height: height)

        for (b, g, r) in frameColors {  // BGRA 順
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
            )
            desc.storageMode = .shared
            desc.usage = [.shaderRead, .shaderWrite]
            guard let tex = device.makeTexture(descriptor: desc) else {
                Issue.record("texture creation failed")
                return
            }
            // BGRA で塗る
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                pixels[i] = b
                pixels[i + 1] = g
                pixels[i + 2] = r
                pixels[i + 3] = 255
            }
            pixels.withUnsafeBytes { buf in
                tex.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: buf.baseAddress!,
                    bytesPerRow: width * 4
                )
            }
            exporter.captureFrame(texture: tex, device: device, commandQueue: queue)
        }

        #expect(exporter.frameCount == frameColors.count)

        let outPath = NSTemporaryDirectory() + "metaphor_gif_e2e_\(UUID().uuidString).gif"
        try exporter.endRecord(to: outPath)
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        // ファイル存在 + フレーム数の確認
        #expect(FileManager.default.fileExists(atPath: outPath))
        let url = URL(fileURLWithPath: outPath) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil) else {
            Issue.record("Failed to read back GIF")
            return
        }
        #expect(CGImageSourceGetCount(src) == frameColors.count)
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
