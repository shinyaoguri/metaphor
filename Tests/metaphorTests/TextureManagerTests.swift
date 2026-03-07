import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

@Suite("TextureManager", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextureManagerTests {

    @Test("init with default parameters")
    func defaultInit() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 1920, height: 1080)
        #expect(tm.width == 1920)
        #expect(tm.height == 1080)
        #expect(tm.sampleCount == 4)
    }

    @Test("init with MSAA disabled")
    func msaaDisabled() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 800, height: 600, sampleCount: 1)
        #expect(tm.sampleCount == 1)
        #expect(tm.colorTexture.width == 800)
        #expect(tm.colorTexture.height == 600)
    }

    @Test("colorTexture dimensions match init")
    func colorTextureDimensions() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 512, height: 256)
        #expect(tm.colorTexture.width == 512)
        #expect(tm.colorTexture.height == 256)
    }

    @Test("depthTexture dimensions match init")
    func depthTextureDimensions() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 512, height: 256)
        #expect(tm.depthTexture.width == 512)
        #expect(tm.depthTexture.height == 256)
    }

    @Test("renderPassDescriptor is configured")
    func renderPassDescriptor() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 100, height: 100)
        let rpd = tm.renderPassDescriptor
        #expect(rpd.colorAttachments[0].texture != nil)
        #expect(rpd.depthAttachment.texture != nil)
    }

    @Test("aspectRatio calculation")
    func aspectRatio() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 1920, height: 1080)
        expectApproxEqual(tm.aspectRatio, 1920.0 / 1080.0)
    }

    @Test("aspectRatio for square")
    func aspectRatioSquare() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 512, height: 512)
        expectApproxEqual(tm.aspectRatio, 1.0)
    }

    @Test("setClearColor updates renderPassDescriptor")
    func setClearColor() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 100, height: 100)
        tm.setClearColor(MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        let clearColor = tm.renderPassDescriptor.colorAttachments[0].clearColor
        #expect(clearColor.red == 1.0)
        #expect(clearColor.green == 0.0)
    }

    @Test("resize creates new manager with correct dimensions")
    func resize() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager(device: device, width: 800, height: 600)
        let resized = try tm.resize(width: 1024, height: 768)
        #expect(resized.width == 1024)
        #expect(resized.height == 768)
    }

    @Test("fullHD convenience")
    func fullHD() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager.fullHD(device: device)
        #expect(tm.width == 1920)
        #expect(tm.height == 1080)
    }

    @Test("square convenience")
    func square() throws {
        let device = MetalTestHelper.device!
        let tm = try TextureManager.square(device: device, size: 256)
        #expect(tm.width == 256)
        #expect(tm.height == 256)
    }
}
