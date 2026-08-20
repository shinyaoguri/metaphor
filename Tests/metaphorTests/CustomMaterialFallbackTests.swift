import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// フラグメントのみのカスタムマテリアルが組み込み形状に効くことを画素で固定する（Issue #717）。
///
/// インスタンス経路の `buffer(1)` は `InstancedSceneUniforms` で、カスタムシェーダーが
/// 読む `Canvas3DUniforms` と別レイアウト。混ぜると頂点が画面外へ飛び「何も描かれない」
/// になるため、カスタムマテリアル中はイミディエイト経路へ落ちるのが契約。ここでは
/// 「実際に絵が出ること」を、バッチに乗りやすい素直な描き方（単発 box /
/// `drawInstanced` / 記録 → 再生経路）それぞれで検証する。
@Suite("CustomMaterial fragment-only fallback", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CustomMaterialFallbackTests {

    private static let size = 128

    /// box(40) を translate(64, 64, 0) で描いたときの中心。
    private static let center = (x: 64, y: 64)

    /// 背景しか無いはずの隅。
    private static let corner = (x: 4, y: 4)

    /// 前文（#713 で自動付与）だけに依存する、フラグメント関数だけのソース。
    /// ライティングを通らず単色を返すので、期待画素が環境に依らず確定する。
    private static let solidRedSource = """
        fragment float4 fallbackSolidRed(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return float4(1.0, 0.0, 0.0, 1.0);
        }
        """

    private func pixel(_ image: GoldenImage, _ p: (x: Int, y: Int)) -> SIMD3<Int> {
        let i = (p.y * image.width + p.x) * 4
        return SIMD3(Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
    }

    /// 黒背景に、フラグメントのみのカスタムマテリアルで単発の box を描く。
    private func drawSolidRedBox(_ c: SketchContext) {
        c.background(Color(r: 0, g: 0, b: 0))
        c.noStroke()
        guard let material = try? c.createMaterial(
            source: Self.solidRedSource, fragmentFunction: "fallbackSolidRed")
        else {
            Issue.record("カスタムマテリアルを作れなかった")
            return
        }
        c.material(material)
        // 透視投影で手前の面が拡大されるため、大きい box は 128px の画面を覆い尽くして
        // 「隅は背景のまま」の検証ができなくなる。box(40) なら中心 ±25px 程度に収まる。
        c.pushMatrix()
        c.translate(64, 64, 0)
        c.box(40)
        c.popMatrix()
    }

    @Test("フラグメントのみのカスタムマテリアルで box が描かれる（即時経路）")
    func rendersOnImmediatePath() throws {
        let image = try OffscreenSketchHarness.render(size: Self.size, draw: drawSolidRedBox)

        #expect(pixel(image, Self.center) == SIMD3(255, 0, 0),
                "box が消えている: center=\(pixel(image, Self.center)) (#717)")
        #expect(pixel(image, Self.corner) == SIMD3(0, 0, 0), "背景まで塗られている")
    }

    @Test("記録 → 再生経路（影オン）でも描かれる")
    func rendersOnRecordedPath() throws {
        let image = try OffscreenSketchHarness.render(
            size: Self.size, mode: .shadows, draw: drawSolidRedBox)

        #expect(pixel(image, Self.center) == SIMD3(255, 0, 0),
                "記録 → 再生経路で box が消えている: center=\(pixel(image, Self.center)) (#717)")
        #expect(pixel(image, Self.corner) == SIMD3(0, 0, 0), "背景まで塗られている")
    }

    @Test("drawInstanced でも全インスタンスが描かれる")
    func rendersOnExplicitInstancedPath() throws {
        // 4 象限に 1 つずつ。y 反転があっても配置が対称なので判定は変わらない。
        let positions: [SIMD3<Float>] = [
            SIMD3(38, 38, 0), SIMD3(90, 38, 0), SIMD3(38, 90, 0), SIMD3(90, 90, 0),
        ]
        let image = try OffscreenSketchHarness.render(size: Self.size) { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            guard let material = try? c.createMaterial(
                source: Self.solidRedSource, fragmentFunction: "fallbackSolidRed"),
                let mesh = try? Mesh.box(
                    device: c.renderer.device, width: 24, height: 24, depth: 24)
            else {
                Issue.record("カスタムマテリアルまたはメッシュを作れなかった")
                return
            }
            c.material(material)
            c.drawInstanced(mesh, transforms: positions.map { float4x4(translation: $0) })
        }

        for p in [(38, 38), (90, 38), (38, 90), (90, 90)] {
            #expect(pixel(image, (x: p.0, y: p.1)) == SIMD3(255, 0, 0),
                    "(\(p.0), \(p.1)) のインスタンスが消えている (#717)")
        }
        #expect(pixel(image, (x: 64, y: 4)) == SIMD3(0, 0, 0), "背景まで塗られている")
    }
}
