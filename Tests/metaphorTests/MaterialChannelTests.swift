import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// マテリアル色の 3 チャンネル版（Issue #700）を固定する。
///
/// `fill` / `stroke` / `background` / `tint` / `ambientLight` は 3 チャンネルを
/// `colorMode` のレンジ基準（既定 0〜255）で受けるのに、`emissive` / `specular` だけが
/// `Color`（0〜1）とグレースケールしか受けなかった。同じ行に並べるとスケールが行き来する。
///
/// ここで固定したいのは 3 点:
///
/// - 3 チャンネル版が `Color` 版と**同じ結果**になる（レンジの解釈が `fill` と揃っている）
/// - `colorMode` の変更に追従する（0〜255 決め打ちではない）
/// - `SIMD4` の w に同居する `shininess` / `metallic` を**壊さない**
@Suite("Material channel args", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MaterialChannelTests {

    private func makeCanvas3D() throws -> Canvas3D {
        let renderer = try MetaphorRenderer()
        return try Canvas3D(renderer: renderer)
    }

    private func expectClose(
        _ actual: SIMD4<Float>, _ expected: SIMD3<Float>, _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(actual.x - expected.x) < 0.001 && abs(actual.y - expected.y) < 0.001
                && abs(actual.z - expected.z) < 0.001,
            "\(what): \(actual.x), \(actual.y), \(actual.z) != \(expected)",
            sourceLocation: sourceLocation)
    }

    // MARK: - Color 版との一致

    @Test("emissive(v1,v2,v3) は既定レンジ 0〜255 で Color 版と一致する")
    func emissiveChannelsMatchColor() throws {
        let canvas3D = try makeCanvas3D()

        canvas3D.emissive(214, 168, 255)
        let byChannels = canvas3D.currentMaterial.emissiveAndMetallic

        canvas3D.emissive(Color(r: 214 / 255, g: 168 / 255, b: 255 / 255))
        let byColor = canvas3D.currentMaterial.emissiveAndMetallic

        expectClose(byChannels, SIMD3(byColor.x, byColor.y, byColor.z), "emissive が Color 版と違う")
    }

    @Test("specular(v1,v2,v3) は既定レンジ 0〜255 で Color 版と一致する")
    func specularChannelsMatchColor() throws {
        let canvas3D = try makeCanvas3D()

        canvas3D.specular(214, 168, 255)
        let byChannels = canvas3D.currentMaterial.specularAndShininess

        canvas3D.specular(Color(r: 214 / 255, g: 168 / 255, b: 255 / 255))
        let byColor = canvas3D.currentMaterial.specularAndShininess

        expectClose(byChannels, SIMD3(byColor.x, byColor.y, byColor.z), "specular が Color 版と違う")
    }

    // MARK: - colorMode 追従

    @Test("colorMode(.rgb, 1) の下では 0〜1 として解釈される")
    func channelsFollowColorMode() throws {
        let canvas3D = try makeCanvas3D()
        canvas3D.colorMode(.rgb, 1)

        canvas3D.emissive(0.84, 0.66, 1)
        expectClose(
            canvas3D.currentMaterial.emissiveAndMetallic, SIMD3(0.84, 0.66, 1),
            "emissive が colorMode に追従していない")

        canvas3D.specular(0.84, 0.66, 1)
        expectClose(
            canvas3D.currentMaterial.specularAndShininess, SIMD3(0.84, 0.66, 1),
            "specular が colorMode に追従していない")
    }

    // MARK: - 同居する w を壊さない

    @Test("emissive(v1,v2,v3) は metallic を、specular(v1,v2,v3) は shininess を保つ")
    func channelsPreserveFourthComponent() throws {
        let canvas3D = try makeCanvas3D()

        canvas3D.metallic(0.7)
        canvas3D.emissive(255, 0, 0)
        #expect(
            abs(canvas3D.currentMaterial.emissiveAndMetallic.w - 0.7) < 0.001,
            "emissive が metallic を潰した: \(canvas3D.currentMaterial.emissiveAndMetallic.w)")

        canvas3D.shininess(64)
        canvas3D.specular(255, 0, 0)
        #expect(
            canvas3D.currentMaterial.specularAndShininess.w == 64,
            "specular が shininess を潰した: \(canvas3D.currentMaterial.specularAndShininess.w)")
    }

    // MARK: - 上位層の転送

    @Test("SketchContext の 3 チャンネル版が正しい成分へ届く")
    func sketchContextForwardsToTheRightComponent() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        // emissive と specular を別の色で呼び、転送先を取り違えていれば落ちる。
        context.emissive(255, 0, 0)
        context.specular(0, 0, 255)
        expectClose(canvas3D.currentMaterial.emissiveAndMetallic, SIMD3(1, 0, 0), "context.emissive")
        expectClose(canvas3D.currentMaterial.specularAndShininess, SIMD3(0, 0, 1), "context.specular")
    }
}
