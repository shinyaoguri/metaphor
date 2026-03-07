import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

@Suite("MetaphorRenderer", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MetaphorRendererTests {

    @Test("default init creates 1920x1080")
    func defaultInit() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.textureManager.width == 1920)
        #expect(renderer.textureManager.height == 1080)
    }

    @Test("custom size init")
    func customSize() throws {
        let renderer = try MetaphorRenderer(width: 800, height: 600)
        #expect(renderer.textureManager.width == 800)
        #expect(renderer.textureManager.height == 600)
    }

    @Test("device has a name")
    func deviceNonNil() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.device.name.isEmpty == false)
    }

    @Test("commandQueue is bound to same device")
    func commandQueueNonNil() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.commandQueue.device === renderer.device)
    }

    @Test("shaderLibrary has builtin shaders registered")
    func shaderLibraryAccessible() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.shaderLibrary.hasLibrary(for: ShaderLibrary.BuiltinKey.blit))
        #expect(renderer.shaderLibrary.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2D))
    }

    @Test("depthStencilCache returns valid states")
    func depthStencilCacheAccessible() throws {
        let renderer = try MetaphorRenderer()
        let state = renderer.depthStencilCache.state(for: .readWrite)
        #expect(state != nil)
    }

    @Test("feedbackEnabled defaults to false")
    func feedbackDefault() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.feedbackEnabled == false)
    }

    @Test("isOfflineRendering defaults to false")
    func offlineRenderingDefault() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.isOfflineRendering == false)
    }

    @Test("offlineFrameRate default is 60")
    func offlineFrameRateDefault() throws {
        let renderer = try MetaphorRenderer()
        expectApproxEqual(renderer.offlineFrameRate, 60.0, epsilon: 0.1)
    }

    @Test("frameBufferIndex starts at 0")
    func frameBufferIndexInit() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.frameBufferIndex == 0)
    }

    @Test("resizeCanvas updates dimensions")
    func resizeCanvas() throws {
        let renderer = try MetaphorRenderer(width: 800, height: 600)
        renderer.resizeCanvas(width: 1024, height: 768)
        #expect(renderer.textureManager.width == 1024)
        #expect(renderer.textureManager.height == 768)
    }

    @Test("setClearColor updates textureManager clearColor")
    func setClearColor() throws {
        let renderer = try MetaphorRenderer()
        renderer.setClearColor(1.0, 0.5, 0.0, 1.0)
        let cc = renderer.textureManager.renderPassDescriptor.colorAttachments[0].clearColor
        #expect(abs(cc.red - 1.0) < 0.01)
        #expect(abs(cc.green - 0.5) < 0.01)
        #expect(abs(cc.blue - 0.0) < 0.01)
    }

    @Test("addPostEffect and clearPostEffects")
    func postEffects() throws {
        let renderer = try MetaphorRenderer()
        renderer.addPostEffect(InvertEffect())
        renderer.clearPostEffects()
        // clearPostEffects 後もクラッシュせず正常に動作する
        renderer.addPostEffect(GrayscaleEffect())
    }

    @Test("previousFrameTexture is nil by default")
    func previousFrameTextureDefault() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.previousFrameTexture == nil)
    }
}
