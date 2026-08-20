import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// 輝度抽出だけを行うエフェクト。`BloomEffect` の 1 手順目を単体で通すためのもの。
///
/// `BloomEffect` をそのまま通すと、最後の合成が α を `base.a`（元画像の α）で
/// 上書きしてしまい、抽出が書いた α を観測できない。
@MainActor
private final class BloomExtractOnlyEffect: PostEffect {
    let name = "bloomExtractOnly"
    let threshold: Float

    init(threshold: Float) {
        self.threshold = threshold
    }

    func apply(
        input: MTLTexture, output: MTLTexture,
        commandBuffer: MTLCommandBuffer, context: PostEffectContext
    ) {
        let params = PostProcessParams(
            texelSize: SIMD2(1.0 / Float(input.width), 1.0 / Float(input.height)),
            intensity: 1.0, threshold: threshold
        )
        context.renderPass(
            commandBuffer: commandBuffer, input: input, output: output,
            fragmentName: PostProcessShaders.FunctionName.postBloomExtract, params: params
        )
    }
}

/// bloom の輝度抽出が α を `1.0` に潰さないことを固定する（Issue #849 / ADR-0012 の規範 5）。
///
/// ポストプロセスの中間テクスチャは premultiplied alpha（ADR-0012 の規範 2）で、
/// `PostEffect` は premultiplied を受け取り premultiplied を返す。輝度抽出は
/// 「rgb を輝度に応じて弱める」処理なので、**α は素通し**でなければならない。
/// `1.0` 固定だと、透明な領域まで不透明を名乗ることになる。
@Suite("Bloom extract alpha", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct BloomExtractAlphaTests {
    private static let width = 32
    private static let height = 32

    /// 一様な premultiplied 値で塗った入力テクスチャ。
    private func makeSource(
        device: MTLDevice, commandQueue: MTLCommandQueue,
        r: Double, g: Double, b: Double, a: Double
    ) throws -> MTLTexture {
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
        pass.colorAttachments[0].clearColor = MTLClearColor(red: r, green: g, blue: b, alpha: a)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw TestHelperError.noDevice
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }

    /// 輝度抽出だけを 1 回通した結果を読み戻す。
    private func extract(
        r: Double, g: Double, b: Double, a: Double, threshold: Float = 0.2
    ) throws -> [UInt8] {
        let device = MetalTestHelper.device!
        let commandQueue = device.makeCommandQueue()!
        let shaderLibrary = try ShaderLibrary(device: device)
        let pipeline = try PostProcessPipeline(
            device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
        )
        pipeline.add(BloomExtractOnlyEffect(threshold: threshold))

        let source = try makeSource(
            device: device, commandQueue: commandQueue, r: r, g: g, b: b, a: a
        )
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw TestHelperError.noDevice
        }
        let output = pipeline.apply(source: source, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let image = try GoldenImage.readback(texture: output, commandQueue: commandQueue)
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return Array(image.rgba[i..<(i + 4)])
    }

    @Test("半透明の明るい領域で α が素通しされる（#849）")
    func alphaIsPreservedForTranslucentInput() throws {
        // premultiplied な中間グレー（straight で白・α=0.5 に相当）
        let px = try extract(r: 0.5, g: 0.5, b: 0.5, a: 0.5)
        // 修正前はここが 255 だった（不透明度 50% の領域が不透明を名乗る）
        #expect(abs(Int(px[3]) - 128) <= 2, "α が 128 ではなく \(px[3])")
    }

    @Test("完全に透明な領域は透明のまま（境界値）")
    func fullyTransparentInputStaysTransparent() throws {
        let px = try extract(r: 0, g: 0, b: 0, a: 0)
        // 修正前は 255。何も無いところが不透明を名乗っていた
        #expect(px[3] == 0, "α が 0 ではなく \(px[3])")
    }

    @Test("不透明な領域は不透明のまま（境界値）")
    func opaqueInputStaysOpaque() throws {
        let px = try extract(r: 0.8, g: 0.8, b: 0.8, a: 1.0)
        #expect(px[3] == 255, "α が 255 ではなく \(px[3])")
    }

    @Test("rgb は α の扱いに影響されない（絵は変わらない）")
    func rgbIsUnchanged() throws {
        // brightness = 0.502（輝度の重みは合計 1.0）、threshold 0.2 なので
        // contribution = (0.502 - 0.2) / 0.502 = 0.602、rgb = 128 * 0.602 = 77
        let px = try extract(r: 0.5, g: 0.5, b: 0.5, a: 0.5)
        for (i, name) in ["R", "G", "B"].enumerated() {
            #expect(abs(Int(px[i]) - 77) <= 2, "\(name) が 77 ではなく \(px[i])")
        }
    }
}
