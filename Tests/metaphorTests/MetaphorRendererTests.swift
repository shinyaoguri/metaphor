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

    // MARK: - Headless rendering (live-viewer Phase 1a contract)

    /// ヘッドレスモードの中核となる不変条件: `configure(view:)` を呼ばずに
    /// 外部ループから `renderFrame()` を駆動しても、`onDraw` が呼ばれ、
    /// オフスクリーンテクスチャにクリアカラーが反映される。
    /// 将来 `renderFrame()` に view/drawable 依存が入り込んだら、このテストが落ちる。
    @Test("renderFrame produces output without a configured view")
    func headlessRenderFrameWithoutView() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        // ヘッドレスモードと同条件: configure(view:) を呼ばず外部ループで駆動。
        renderer.useExternalRenderLoop = true
        renderer.setClearColor(0, 0, 1, 1)  // 青

        var drawInvoked = false
        renderer.onDraw = { _, _ in drawInvoked = true }

        // view / drawable 無しで1フレームをレンダリング。
        renderer.renderFrame()

        #expect(drawInvoked, "onDraw should be invoked by renderFrame without a view")

        let p = try readbackCenterPixel(renderer: renderer)
        #expect(p.b > 250, "Headless clear should be blue: B=\(p.b)")
        #expect(p.r < 8, "Headless clear R=\(p.r)")
        #expect(p.g < 8, "Headless clear G=\(p.g)")
    }

    /// ヘッドレスモードのフレーム出力先 Syphon サーバーが起動できる。
    @Test("startSyphonServer activates the headless frame sink")
    func headlessSyphonServerActivates() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        #expect(renderer.syphonOutput == nil)
        renderer.startSyphonServer(name: "metaphor-headless-test")
        #expect(renderer.syphonOutput?.isActive == true)
    }

    /// オフスクリーンカラーテクスチャの中心ピクセルを読み戻すヘルパー（BGRA→RGB）。
    private func readbackCenterPixel(
        renderer: MetaphorRenderer
    ) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let staging = try #require(renderer.device.makeTexture(descriptor: desc))

        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        let blit = try #require(cb.makeBlitCommandEncoder())
        blit.copy(
            from: renderer.textureManager.colorTexture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: staging,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var px = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(
            &px, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
        )
        let off = ((h / 2) * w + (w / 2)) * 4
        return (r: px[off + 2], g: px[off + 1], b: px[off + 0])  // BGRA → RGB
    }
}
