import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `VignetteEffect` の `intensity` が「0 で無効・1 で最も強い」強度であることを
/// 画素で固定する（Issue #684）。
///
/// 以前は `intensity` が「黒に落ちきる半径」で、値が大きいほど**弱い**という
/// 逆向きの意味だった。既定値（0.5）のままだと `dist >= 0.5` の領域 —— 16:9 の
/// 画面の大半 —— が純黒に潰れ、`addPostEffect(VignetteEffect())` と書いただけで
/// 作品が黒くなっていた。
@Suite("VignetteEffect intensity", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct VignetteEffectTests {

    private static let width = 128
    private static let height = 72  // 16:9（隅が dist = 0.707 に届く形）

    /// 一様なグレーで塗った入力テクスチャ。
    private func makeSource(device: MTLDevice, commandQueue: MTLCommandQueue) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: Self.width, height: Self.height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TestHelperError.noDevice
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw TestHelperError.noDevice
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }

    /// `VignetteEffect` を 1 回だけ通した結果を読み戻します。
    private func applyVignette(_ effect: VignetteEffect?) throws -> GoldenImage {
        let device = MetalTestHelper.device!
        let commandQueue = device.makeCommandQueue()!
        let shaderLibrary = try ShaderLibrary(device: device)
        let pipeline = try PostProcessPipeline(
            device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
        )
        if let effect { pipeline.add(effect) }

        let source = try makeSource(device: device, commandQueue: commandQueue)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw TestHelperError.noDevice
        }
        let output = pipeline.apply(source: source, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return try GoldenImage.readback(texture: output, commandQueue: commandQueue)
    }

    private func pixel(_ image: GoldenImage, x: Int, y: Int) -> Int {
        Int(image.rgba[(y * image.width + x) * 4 + 1])  // G チャンネル（グレーなので代表値）
    }

    private var center: (x: Int, y: Int) { (Self.width / 2, Self.height / 2) }
    private var corner: (x: Int, y: Int) { (1, 1) }

    // MARK: - 0 は無効

    @Test("intensity 0 はどの画素も暗くしない")
    func zeroIntensityIsIdentity() throws {
        let untouched = try applyVignette(nil)
        let vignetted = try applyVignette(VignetteEffect(intensity: 0))
        #expect(vignetted.rgba == untouched.rgba)
    }

    // MARK: - 既定値で絵が壊れない（本 Issue の眼目）

    @Test("既定の VignetteEffect() で画面の大半が残る")
    func defaultKeepsThePicture() throws {
        let untouched = try applyVignette(nil)
        let vignetted = try applyVignette(VignetteEffect())

        // 旧実装では隅が純黒に潰れ、平均輝度が元の 2% まで落ちていた（#684 の実測）。
        let before = meanLuminance(untouched)
        let after = meanLuminance(vignetted)
        #expect(after > before * 0.6)

        // 中央は素通しのまま、隅だけが落ちる。
        #expect(pixel(vignetted, x: center.x, y: center.y) == pixel(untouched, x: center.x, y: center.y))
        #expect(pixel(vignetted, x: corner.x, y: corner.y) < pixel(untouched, x: corner.x, y: corner.y))
    }

    // MARK: - 強度として単調

    @Test("intensity を上げるほど暗くなる")
    func higherIntensityIsDarker() throws {
        let weak = try applyVignette(VignetteEffect(intensity: 0.25))
        let medium = try applyVignette(VignetteEffect(intensity: 0.5))
        let strong = try applyVignette(VignetteEffect(intensity: 1.0))

        #expect(meanLuminance(weak) > meanLuminance(medium))
        #expect(meanLuminance(medium) > meanLuminance(strong))
        // 最強でも中央は残る（画面全部が黒くはならない）。
        #expect(pixel(strong, x: center.x, y: center.y) > 0)
    }

    @Test("範囲外の intensity はクランプされる")
    func outOfRangeIsClamped() throws {
        let atZero = try applyVignette(VignetteEffect(intensity: 0))
        let belowZero = try applyVignette(VignetteEffect(intensity: -2))
        #expect(belowZero.rgba == atZero.rgba)

        let atOne = try applyVignette(VignetteEffect(intensity: 1))
        let aboveOne = try applyVignette(VignetteEffect(intensity: 5))
        #expect(aboveOne.rgba == atOne.rgba)
    }

    private func meanLuminance(_ image: GoldenImage) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: image.rgba.count, by: 4) {
            sum += 0.2126 * Double(image.rgba[i])
                + 0.7152 * Double(image.rgba[i + 1])
                + 0.0722 * Double(image.rgba[i + 2])
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }
}
