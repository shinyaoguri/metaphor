import Testing
import Metal
import simd
@testable import MetaphorCore
@testable import MetaphorRenderGraph

@Suite("RenderGraph", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct RenderGraphTests {
    let device: MTLDevice

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        self.device = device
    }

    // MARK: - SourcePass Tests

    @Test("SourcePass creates valid offscreen texture")
    func sourcePassCreatesTexture() throws {
        let pass = try SourcePass(label: "test", device: device, width: 256, height: 256)
        #expect(pass.label == "test")
        #expect(pass.output != nil)
        #expect(pass.output?.width == 256)
        #expect(pass.output?.height == 256)
    }

    @Test("SourcePass onDraw callback is invoked")
    func sourcePassCallbackInvoked() throws {
        let pass = try SourcePass(label: "cb", device: device, width: 64, height: 64)
        var called = false
        pass.onDraw = { _, _ in called = true }

        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            return
        }

        let renderer = try MetaphorRenderer(
            device: device,
            width: 64,
            height: 64
        )
        pass.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(called)
    }

    @Test("SourcePass with different sizes")
    func sourcePassDifferentSizes() throws {
        let small = try SourcePass(label: "s", device: device, width: 32, height: 32)
        let large = try SourcePass(label: "l", device: device, width: 1024, height: 512)
        #expect(small.output?.width == 32)
        #expect(large.output?.width == 1024)
        #expect(large.output?.height == 512)
    }

    // MARK: - EffectPass Tests

    @Test("EffectPass wraps upstream pass")
    func effectPassWrapsUpstream() throws {
        let source = try SourcePass(label: "src", device: device, width: 128, height: 128)
        let shaderLib = try ShaderLibrary(device: device)
        let queue = device.makeCommandQueue()!
        let effect = try EffectPass(
            source,
            effects: [],
            device: device,
            commandQueue: queue,
            shaderLibrary: shaderLib
        )
        #expect(effect.label == "effect(src)")
    }

    // MARK: - RenderGraph Tests

    @Test("RenderGraph with single SourcePass produces output")
    func graphSingleSourcePass() throws {
        let pass = try SourcePass(label: "root", device: device, width: 64, height: 64)
        pass.onDraw = { encoder, _ in
            // Just end encoding, no actual drawing needed
        }

        let graph = RenderGraph(root: pass)
        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            return
        }

        let renderer = try MetaphorRenderer(
            device: device,
            width: 64,
            height: 64
        )
        let output = graph.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(output != nil)
        #expect(output?.width == 64)
    }

    @Test("shared node in a diamond executes once per frame")
    func diamondSharedNodeExecutesOnce() throws {
        // MergePass(scene, EffectPass(scene)) の diamond。scene は2経路から
        // 到達されるが、フレームトークンによるメモ化で onDraw は1回だけ走る。
        let scene = try SourcePass(label: "scene", device: device, width: 64, height: 64)
        var drawCount = 0
        scene.onDraw = { _, _ in drawCount += 1 }

        let shaderLib = try ShaderLibrary(device: device)
        let queue = device.makeCommandQueue()!
        let effect = try EffectPass(
            scene, effects: [], device: device, commandQueue: queue, shaderLibrary: shaderLib
        )
        let merge = try MergePass(
            scene, effect, blend: .add, device: device, shaderLibrary: shaderLib
        )
        let graph = RenderGraph(root: merge)

        let renderer = try MetaphorRenderer(device: device, width: 64, height: 64)
        guard let cmdBuf = queue.makeCommandBuffer() else { return }
        graph.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        #expect(drawCount == 1)
    }

    // MARK: - MergePass.BlendType Tests

    @Test("BlendType cases have correct raw indices")
    func blendTypeIndices() {
        #expect(MergePass.BlendType.add.rawIndex == 0)
        #expect(MergePass.BlendType.alpha.rawIndex == 1)
        #expect(MergePass.BlendType.multiply.rawIndex == 2)
        #expect(MergePass.BlendType.screen.rawIndex == 3)
    }

    @Test("BlendType has all 4 cases")
    func blendTypeAllCases() {
        #expect(MergePass.BlendType.allCases.count == 4)
    }

    // MARK: - RenderPassNode Protocol

    @Test("RenderPassNode protocol conformance for SourcePass")
    func sourcePassConformsToProtocol() throws {
        let pass = try SourcePass(label: "proto", device: device, width: 64, height: 64)
        let node: RenderPassNode = pass
        #expect(node.label == "proto")
        #expect(node.output != nil)
    }
}

// MARK: - MergePass 異サイズ・フォーマット（#145）

/// テスト用: 固定テクスチャを出力するだけのノード。
@MainActor
private final class StubTexturePass: RenderPassNode {
    let label: String
    var output: MTLTexture?

    init(label: String, texture: MTLTexture) {
        self.label = label
        self.output = texture
    }

    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {}
}

@Suite("MergePass size/format", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MergePassSizeFormatTests {
    let device = MTLCreateSystemDefaultDevice()!

    private func makeFilledTexture(
        width: Int, height: Int, byte: UInt8, pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        if pixelFormat == .bgra8Unorm {
            let bytes = [UInt8](repeating: byte, count: width * height * 4)
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4
            )
        }
        return tex
    }

    private func readback(_ texture: MTLTexture, queue: MTLCommandQueue) -> [UInt8]? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width, height: texture.height, mipmapped: false
        )
        desc.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: desc),
              let cmdBuf = queue.makeCommandBuffer(),
              let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: staging)
        blit.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        staging.getBytes(
            &bytes, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
        )
        return bytes
    }

    @Test("mismatched input sizes read as transparent black, not undefined")
    func mismatchedSizes() throws {
        let queue = device.makeCommandQueue()!
        let shaderLib = try ShaderLibrary(device: device)

        // A: 64x64 全面 0x40、B: 32x32 全面 0x20
        guard let texA = makeFilledTexture(width: 64, height: 64, byte: 0x40),
              let texB = makeFilledTexture(width: 32, height: 32, byte: 0x20) else {
            Issue.record("Failed to create test textures")
            return
        }
        let passA = StubTexturePass(label: "a", texture: texA)
        let passB = StubTexturePass(label: "b", texture: texB)
        let merge = try MergePass(passA, passB, blend: .add, device: device, shaderLibrary: shaderLib)

        let renderer = try MetaphorRenderer(device: device, width: 64, height: 64)
        guard let cmdBuf = queue.makeCommandBuffer() else { return }
        merge.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        guard let output = merge.output, let bytes = readback(output, queue: queue) else {
            Issue.record("No merge output")
            return
        }

        // B の範囲内（16,16）: A + B = 0x60
        let inside = (16 * 64 + 16) * 4
        #expect(bytes[inside] == 0x60)
        // B の範囲外（48,48）: 修正前は未定義値、修正後は A + 0 = 0x40
        let outside = (48 * 64 + 48) * 4
        #expect(bytes[outside] == 0x40)
        #expect(bytes[outside + 1] == 0x40)
        #expect(bytes[outside + 2] == 0x40)
    }

    @Test("output pixel format follows input A (rgba16Float preserved)")
    func formatPreserved() throws {
        let queue = device.makeCommandQueue()!
        let shaderLib = try ShaderLibrary(device: device)

        guard let texA = makeFilledTexture(width: 32, height: 32, byte: 0, pixelFormat: .rgba16Float),
              let texB = makeFilledTexture(width: 32, height: 32, byte: 0x20) else {
            Issue.record("Failed to create test textures")
            return
        }
        let merge = try MergePass(
            StubTexturePass(label: "a", texture: texA),
            StubTexturePass(label: "b", texture: texB),
            blend: .add, device: device, shaderLibrary: shaderLib
        )

        let renderer = try MetaphorRenderer(device: device, width: 32, height: 32)
        guard let cmdBuf = queue.makeCommandBuffer() else { return }
        merge.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // 修正前は .bgra8Unorm 固定で HDR 入力が暗黙に量子化されていた
        #expect(merge.output?.pixelFormat == .rgba16Float)
    }
}
