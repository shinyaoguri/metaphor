import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

// MARK: - beginShape3D とカスタムマテリアル（#826）

/// `material(_:)` が `beginShape3D` で組んだシェイプにも効くことを画素で固定する（#826）。
///
/// `drawShape3D*`（`Canvas3D+ShapeDrawing.swift`）の即時経路は組み込みパイプラインを
/// 無条件に張っており `currentCustomMaterial` を見ていなかった。一方で記録経路
/// （影オン / `METAPHOR_COMMAND_RECORD`）は一時 Mesh 化して `drawMeshImmediate` へ
/// 落ちるためカスタムパイプラインが張られる。**同じスケッチが経路によって別の絵になる**
/// ので、`.immediate` / `.shadows` の両方で同じ画素になることまで固定する。
///
/// ライティングを通らず単色を返すフラグメントだけのマテリアルを使うので、
/// 期待画素は環境に依らず確定する（`CustomMaterialFallbackTests` と同じ作り）。
@Suite("Canvas3D Shape CustomMaterial", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DShapeCustomMaterialTests {

    private static let size = 64

    /// 前文（#713 で自動付与）だけに依存する、フラグメント関数だけのソース。
    private static let solidRedSource = """
        fragment float4 shapeSolidRed(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return float4(1.0, 0.0, 0.0, 1.0);
        }
        """

    /// テクスチャ経路の `[[stage_in]]` は UV を持つ別の型（`Canvas3DTexVertexOut`）。
    /// テクセルを一切参照せず単色を返すので、「テクスチャよりカスタムが勝つ」が測れる。
    private static let solidRedTexturedSource = """
        fragment float4 shapeSolidRedTextured(
            Canvas3DTexVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]],
            texture2d<float> tex [[texture(0)]]
        ) {
            return float4(1.0, 0.0, 0.0, 1.0);
        }
        """

    private func pixel(_ fb: GoldenImage, _ x: Int, _ y: Int) -> SIMD3<Int> {
        let i = (y * fb.width + x) * 4
        return SIMD3(Int(fb.rgba[i]), Int(fb.rgba[i + 1]), Int(fb.rgba[i + 2]))
    }

    private func center(_ fb: GoldenImage) -> SIMD3<Int> {
        pixel(fb, fb.width / 2, fb.height / 2)
    }

    /// 画面中央に一辺 40 の板を `beginShape3D` で組む（`Canvas3DShapeFillTests` と同じ形）。
    private func quad(_ ctx: SketchContext) {
        ctx.pushMatrix()
        ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        ctx.beginShape3D()
        ctx.vertex(-20, -20, 0)
        ctx.vertex(20, -20, 0)
        ctx.vertex(20, 20, 0)
        ctx.vertex(-20, 20, 0)
        ctx.endShape3D(.close)
        ctx.popMatrix()
    }

    /// UV 付きの板（`texture()` と組み合わせるとテクスチャ経路へ入る）。
    private func texturedQuad(_ ctx: SketchContext) {
        ctx.pushMatrix()
        ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        ctx.beginShape3D()
        ctx.vertex(-20, -20, 0, 0, 0)
        ctx.vertex(20, -20, 0, 1, 0)
        ctx.vertex(20, 20, 0, 1, 1)
        ctx.vertex(-20, 20, 0, 0, 1)
        ctx.endShape3D(.close)
        ctx.popMatrix()
    }

    /// 全面が青の 1×1 テクスチャ（BGRA8）。カスタムが効いていなければ青が出る。
    private static func solidBlueTexture(device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        // BGRA 並びで青
        let bytes: [UInt8] = [255, 0, 0, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: bytes, bytesPerRow: 4)
        return MImage(texture: tex)
    }

    @Test("カスタムマテリアルが beginShape3D のシェイプに効く",
          arguments: [MainPassMode.immediate, .shadows])
    func customMaterialAppliesToShape(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            guard let material = try? ctx.createMaterial(
                source: Self.solidRedSource, fragmentFunction: "shapeSolidRed")
            else {
                Issue.record("カスタムマテリアルを作れなかった")
                return
            }
            ctx.material(material)
            self.quad(ctx)
        }

        #expect(center(fb) == SIMD3(255, 0, 0),
                "beginShape3D のシェイプにカスタムマテリアルが効いていない: \(center(fb)) — #826")
        #expect(pixel(fb, 2, 2) == SIMD3(0, 0, 0), "背景まで塗られている")
    }

    @Test(".points にもカスタムマテリアルが効く",
          arguments: [MainPassMode.immediate, .shadows])
    func customMaterialAppliesToPoints(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            guard let material = try? ctx.createMaterial(
                source: Self.solidRedSource, fragmentFunction: "shapeSolidRed")
            else {
                Issue.record("カスタムマテリアルを作れなかった")
                return
            }
            ctx.material(material)
            ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            // 点は 0.5 単位角の三角形なので、拾えるだけの大きさへ拡大する
            ctx.scale(30, 30, 30)
            ctx.beginShape3D(.points)
            ctx.vertex(0, 0, 0)
            ctx.endShape3D()
        }

        // 点の三角形は中心のわずかに下（y+）へ張り出すので、重心あたりを見る
        let p = pixel(fb, Self.size / 2, Self.size / 2 + 4)
        #expect(p == SIMD3(255, 0, 0),
                ".points にカスタムマテリアルが効いていない: \(p) — #826")
    }

    @Test("テクスチャを貼ったシェイプでもカスタムマテリアルが勝つ",
          arguments: [MainPassMode.immediate, .shadows])
    func customMaterialAppliesToTexturedShape(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            guard let material = try? ctx.createMaterial(
                source: Self.solidRedTexturedSource, fragmentFunction: "shapeSolidRedTextured"),
                let img = Self.solidBlueTexture(device: ctx.renderer.device)
            else {
                Issue.record("カスタムマテリアルまたはテクスチャを作れなかった")
                return
            }
            ctx.texture(img)
            ctx.material(material)
            self.texturedQuad(ctx)
        }

        #expect(center(fb) == SIMD3(255, 0, 0),
                "テクスチャ経路でカスタムマテリアルが効いていない（青ならテクセルのまま）: \(center(fb)) — #826")
    }

    @Test("noMaterial() すれば組み込みのシェーディングへ戻る",
          arguments: [MainPassMode.immediate, .shadows])
    func noMaterialRestoresBuiltinShading(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            guard let material = try? ctx.createMaterial(
                source: Self.solidRedSource, fragmentFunction: "shapeSolidRed")
            else {
                Issue.record("カスタムマテリアルを作れなかった")
                return
            }
            ctx.material(material)
            ctx.noMaterial()
            ctx.fill(Color(r: 0, g: 1, b: 0))
            self.quad(ctx)
        }

        let c = center(fb)
        #expect(c.x < 32 && c.y > 200 && c.z < 32,
                "noMaterial() 後は fill 色（緑）で塗られるべき: \(c) — #826")
    }
}
