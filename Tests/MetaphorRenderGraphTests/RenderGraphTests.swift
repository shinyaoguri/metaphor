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

// MARK: - MergePass(.alpha) の premultiplied 合成（#831 / ADR-0012）

/// `MergePass` の入力はレンダーターゲットの中身なので premultiplied（ADR-0012 の規範 2）。
/// `.alpha` は `b.rgb + a.rgb * (1 - b.a)` でなければならない。修正前は
/// `b.rgb * b.a + ...` と α を 2 回掛けており、重ねた層が暗くなっていた。
@Suite("MergePass alpha (premultiplied)", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MergePassAlphaTests {
    let device = MTLCreateSystemDefaultDevice()!

    /// BGRA の 8bit 値を敷き詰めたテクスチャを作る。
    ///
    /// 呼び出し側は premultiplied な値（`rgb <= a`）を渡す。
    private func makeSolidTexture(size: Int, b: UInt8, g: UInt8, r: UInt8, a: UInt8) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = b
            bytes[i + 1] = g
            bytes[i + 2] = r
            bytes[i + 3] = a
        }
        tex.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4
        )
        return tex
    }

    /// 2 枚を `.alpha` で合成し、中央画素の BGRA を返す。
    private func mergeAlpha(_ texA: MTLTexture, _ texB: MTLTexture) throws -> [UInt8] {
        let queue = device.makeCommandQueue()!
        let shaderLib = try ShaderLibrary(device: device)
        let merge = try MergePass(
            StubTexturePass(label: "a", texture: texA),
            StubTexturePass(label: "b", texture: texB),
            blend: .alpha, device: device, shaderLibrary: shaderLib
        )

        let renderer = try MetaphorRenderer(device: device, width: texA.width, height: texA.height)
        guard let cmdBuf = queue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return []
        }
        merge.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        guard let output = merge.output else {
            Issue.record("No merge output")
            return []
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: output.pixelFormat,
            width: output.width, height: output.height, mipmapped: false
        )
        desc.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: desc),
              let blitBuf = queue.makeCommandBuffer(),
              let blit = blitBuf.makeBlitCommandEncoder() else {
            Issue.record("Failed to create staging texture")
            return []
        }
        blit.copy(from: output, to: staging)
        blit.endEncoding()
        blitBuf.commit()
        blitBuf.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: output.width * output.height * 4)
        staging.getBytes(
            &bytes, bytesPerRow: output.width * 4,
            from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0
        )
        let center = ((output.height / 2) * output.width + output.width / 2) * 4
        return Array(bytes[center..<(center + 4)])
    }

    /// 8bit の丸め（±2）を許容した比較。
    private func expectBGRA(
        _ actual: [UInt8], b: Int, g: Int, r: Int, a: Int, _ what: String
    ) {
        guard actual.count == 4 else {
            Issue.record("\(what): 画素を読めなかった")
            return
        }
        let expected = [b, g, r, a]
        for (i, name) in ["B", "G", "R", "A"].enumerated() {
            #expect(
                abs(Int(actual[i]) - expected[i]) <= 2,
                "\(what): \(name) が \(expected[i]) ではなく \(actual[i])"
            )
        }
    }

    @Test("premultiplied な前景に α が 2 回掛からない（#831）")
    func alphaOverDoesNotDoubleMultiply() throws {
        // 下地 A: 不透明 rgb(0.600, 0.200, 0.102) = BGRA(26, 51, 153, 255)
        // 前景 B: straight rgb(0.200, 0.800, 0.400) / α=0.502 を premultiplied で格納
        //         = BGRA(51, 102, 26, 128)
        guard let texA = makeSolidTexture(size: 16, b: 26, g: 51, r: 153, a: 255),
              let texB = makeSolidTexture(size: 16, b: 51, g: 102, r: 26, a: 128) else {
            Issue.record("Failed to create test textures")
            return
        }

        // b.rgb + a.rgb * (1 - b.a)
        //   R = 26 + 153 * 0.498 = 102.2 / G = 102 + 51 * 0.498 = 127.4
        //   B = 51 + 26 * 0.498 = 64.0  / A = 128 + 255 * 0.498 = 255
        // 修正前は BGRA(39, 77, 89, 255) と、α を 2 回掛けた分だけ暗かった。
        expectBGRA(try mergeAlpha(texA, texB), b: 64, g: 127, r: 102, a: 255, "半透明の前景を不透明な下地に重ねる")
    }

    @Test("透明な下地への合成は前景そのまま（over の単位元）")
    func alphaOverTransparentIsIdentity() throws {
        guard let texA = makeSolidTexture(size: 16, b: 0, g: 0, r: 0, a: 0),
              let texB = makeSolidTexture(size: 16, b: 128, g: 128, r: 128, a: 128) else {
            Issue.record("Failed to create test textures")
            return
        }
        // 修正前は BGRA(64, 64, 64, 128)。何も無いところへ重ねただけで暗くなっていた。
        expectBGRA(try mergeAlpha(texA, texB), b: 128, g: 128, r: 128, a: 128, "透明な下地へ重ねる")
    }

    @Test("α=0 の前景は下地を変えない（境界値）")
    func alphaOverFullyTransparentForeground() throws {
        guard let texA = makeSolidTexture(size: 16, b: 26, g: 51, r: 153, a: 255),
              let texB = makeSolidTexture(size: 16, b: 0, g: 0, r: 0, a: 0) else {
            Issue.record("Failed to create test textures")
            return
        }
        expectBGRA(try mergeAlpha(texA, texB), b: 26, g: 51, r: 153, a: 255, "α=0 の前景")
    }

    @Test("α=1 の前景は下地を完全に隠す（境界値）")
    func alphaOverFullyOpaqueForeground() throws {
        guard let texA = makeSolidTexture(size: 16, b: 26, g: 51, r: 153, a: 255),
              let texB = makeSolidTexture(size: 16, b: 51, g: 204, r: 102, a: 255) else {
            Issue.record("Failed to create test textures")
            return
        }
        expectBGRA(try mergeAlpha(texA, texB), b: 51, g: 204, r: 102, a: 255, "α=1 の前景")
    }
}
