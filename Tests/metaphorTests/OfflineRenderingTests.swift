import Testing
import Metal
@testable import MetaphorCore

// MARK: - C-13: Offline Deterministic Rendering

@Suite("C-13 Offline Rendering", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct OfflineRenderingTests {

    @Test("offlineFrameRate defaults to 60")
    func defaultFrameRate() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.offlineFrameRate == 60.0)
        #expect(renderer.isOfflineRendering == false)
    }

    @Test("elapsedTime uses frame index in offline mode")
    func offlineElapsedTime() throws {
        let renderer = try MetaphorRenderer()
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = 30.0
        renderer.resetOfflineRendering()

        // フレーム 0 → elapsed = 0
        #expect(renderer.elapsedTime == 0.0)
    }

    @Test("offlineDeltaTime returns correct value")
    func offlineDeltaTime() throws {
        let renderer = try MetaphorRenderer()
        renderer.offlineFrameRate = 30.0
        let dt = renderer.offlineDeltaTime
        #expect(abs(dt - 1.0 / 30.0) < 0.0001)
    }

    @Test("isOfflineRendering can be set directly")
    func setOfflineFlag() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.isOfflineRendering == false)
        renderer.isOfflineRendering = true
        #expect(renderer.isOfflineRendering == true)
        renderer.isOfflineRendering = false
        #expect(renderer.isOfflineRendering == false)
    }

    @Test("resetOfflineRendering resets elapsed to 0")
    func resetOffline() throws {
        let renderer = try MetaphorRenderer()
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = 30.0
        renderer.resetOfflineRendering()
        #expect(renderer.elapsedTime == 0.0)
    }

    @Test("SketchContext offline render API")
    func sketchContextOffline() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        #expect(ctx.isOfflineRendering == false)
        ctx.beginOfflineRender(fps: 24)
        #expect(ctx.isOfflineRendering == true)
        #expect(renderer.offlineFrameRate == 24.0)
        ctx.endOfflineRender()
        #expect(ctx.isOfflineRendering == false)
    }
}
