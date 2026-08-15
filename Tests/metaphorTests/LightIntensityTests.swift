import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// ライトの強度倍率（`intensity`）が直接光に効くことを画素で固定する（Issue #687）。
///
/// シェーダは以前から `lights[i].colorAndIntensity.w` を掛けていたが、API 側が
/// 1.0 に固定していたため触れなかった。ここで固定したいのは 2 点:
///
/// - **既定は 1.0** で、引数を省いた呼び出しは従来と同じ絵になる（後方互換）
/// - PBR の直接光は `albedo / π` で沈むため、`intensity` で持ち上げられる
///   （灯数を増やして明るさを稼がなくてよい）
@Suite("Light intensity", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct LightIntensityTests {

    private static let size = 96

    /// 球のハイライト側にある画素（既定カメラ・光は左上手前から差す）。
    private static let litSurface = (x: 38, y: 38)

    /// オフスクリーン 1 フレームを描いて全画素を読み戻す（影は使わない）。
    private func render(draw: @escaping (SketchContext) -> Void) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        renderer.useExternalRenderLoop = true
        renderer.renderFrame()
        return try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture, commandQueue: renderer.commandQueue)
    }

    private func pixel(_ image: GoldenImage, _ p: (x: Int, y: Int)) -> SIMD3<Int> {
        let i = (p.y * image.width + p.x) * 4
        return SIMD3(Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
    }

    /// 画面全体の平均輝度（0…255）。灯の種類を問わず「明るくなったか」を測る。
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

    /// 中央に置いた球ひとつ。`light` で灯を足す。
    private func sphereScene(
        pbr: Bool = false,
        ambient: Float = 20,
        light: @escaping (SketchContext) -> Void
    ) -> (SketchContext) -> Void {
        return { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.ambientLight(ambient)
            light(c)
            if pbr {
                c.pbr(true)
                c.roughness(0.4)
                c.metallic(0)
            } else {
                c.specular(0)
            }
            c.fill(Color(r: 0.5, g: 0.5, b: 0.5))
            c.pushMatrix()
            c.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            c.sphere(30)
            c.popMatrix()
        }
    }

    // MARK: - 後方互換

    @Test("intensity を省くと 1.0 指定と全画素一致する")
    func defaultIntensityMatchesExplicitOne() throws {
        let implicit = try render(draw: sphereScene { c in
            c.directionalLight(-0.4, 0.6, -0.7)
        })
        let explicit = try render(draw: sphereScene { c in
            c.directionalLight(-0.4, 0.6, -0.7, intensity: 1.0)
        })
        #expect(implicit.rgba == explicit.rgba)
    }

    // MARK: - directionalLight

    @Test("PBR 単灯は intensity で持ち上がる")
    func pbrDirectionalBrightensWithIntensity() throws {
        let dim = try render(draw: sphereScene(pbr: true) { c in
            c.directionalLight(-0.4, 0.6, -0.7)
        })
        let bright = try render(draw: sphereScene(pbr: true) { c in
            c.directionalLight(-0.4, 0.6, -0.7, intensity: 3.0)
        })

        let dimPixel = pixel(dim, Self.litSurface)
        let brightPixel = pixel(bright, Self.litSurface)
        // albedo/π で沈んだ面が、灯を増やさずに明確に明るくなる（#687 の眼目）。
        #expect(brightPixel.x > dimPixel.x + 20)
        #expect(meanLuminance(bright) > meanLuminance(dim))
    }

    @Test("intensity 0 は直接光を消す（黒い灯と同じ絵になる）")
    func zeroIntensityKillsDirectLight() throws {
        let zeroIntensity = try render(draw: sphereScene { c in
            c.directionalLight(-0.4, 0.6, -0.7, intensity: 0)
        })
        // 「灯はあるが色が黒」＝直接光の寄与がゼロ。灯を足さない場合とは
        // アンビエントの既定挿入（ensureAmbientIfFirstLight）が違うので、
        // 比較対象は「黒い灯」にする。
        let blackLight = try render(draw: sphereScene { c in
            c.directionalLight(-0.4, 0.6, -0.7, color: Color(r: 0, g: 0, b: 0))
        })
        #expect(zeroIntensity.rgba == blackLight.rgba)

        let lit = try render(draw: sphereScene { c in
            c.directionalLight(-0.4, 0.6, -0.7)
        })
        #expect(meanLuminance(lit) > meanLuminance(zeroIntensity))
    }

    // MARK: - pointLight / spotLight

    @Test("pointLight にも intensity が効く")
    func pointLightRespectsIntensity() throws {
        let dim = try render(draw: sphereScene { c in
            c.pointLight(20, 20, 120, color: .white, falloff: 0.001)
        })
        let bright = try render(draw: sphereScene { c in
            c.pointLight(20, 20, 120, color: .white, falloff: 0.001, intensity: 2.5)
        })
        #expect(meanLuminance(bright) > meanLuminance(dim))
    }

    @Test("spotLight にも intensity が効く")
    func spotLightRespectsIntensity() throws {
        let dim = try render(draw: sphereScene { c in
            c.spotLight(48, 48, 160, 0, 0, -1, angle: .pi / 4, falloff: 0.001)
        })
        let bright = try render(draw: sphereScene { c in
            c.spotLight(
                48, 48, 160, 0, 0, -1, angle: .pi / 4, falloff: 0.001, intensity: 2.5
            )
        })
        #expect(meanLuminance(bright) > meanLuminance(dim))
    }

    // MARK: - 内部状態

    @Test("intensity は colorAndIntensity.w へそのまま入る")
    func intensityGoesToLightBuffer() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.directionalLight(0, 1, 0, color: .white, intensity: 2.5)
        canvas3D.pointLight(0, 0, 10, color: .white, falloff: 0.1, intensity: 0.25)

        #expect(canvas3D.lightArray.count == 2)
        #expect(canvas3D.lightArray[0].colorAndIntensity.w == 2.5)
        #expect(canvas3D.lightArray[1].colorAndIntensity.w == 0.25)
    }
}
