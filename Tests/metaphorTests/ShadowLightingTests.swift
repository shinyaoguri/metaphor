import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// 影の減衰が「どの項に掛かるか」を画素で固定する（Issue #364）。
///
/// 規範（Processing / p5.js / 一般的なシャドウマッピング）では、影は**直接光
/// （diffuse + specular）だけ**を減衰させる。環境光（ambient）と自発光（emissive）は
/// 遮蔽物の裏にも回り込む／光源に依存しないので、影の中でも残らなければならない。
/// PBR の ambient occlusion は逆に、影の内外を問わず ambient に掛かり続ける。
///
/// これらは「影の中が真っ黒になる」系の退行を、シーン全体の見た目ではなく
/// **1 画素の物理的な意味**で捉えるためのテスト。
@Suite("Shadow lighting composition", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ShadowLightingTests {

    private static let size = 128

    /// 影を受ける床の**影の中**にある画素。
    private static let shadowedFloor = (x: 64, y: 92)
    /// 同じ床の、影の外にある画素（比較用）。
    private static let litFloor = (x: 30, y: 92)

    // MARK: - ハーネス

    /// `GoldenImageTests` と同じ結線でオフスクリーン 1 フレームを描き、全画素を読み戻す。
    ///
    /// - Parameters:
    ///   - instanceCapacity: 指定するとインスタンスバッチの容量を差し替え、2 個目以降の
    ///     3D 描画を非インスタンス（イミディエイト）経路へ落とす（#391）。
    ///   - inspect: 1 フレーム描画後に `Canvas3D` を検査するフック。
    private func render(
        shadows: Bool,
        instanceCapacity: Int? = nil,
        inspect: ((Canvas3D) -> Void)? = nil,
        draw: @escaping (SketchContext) -> Void
    ) throws -> GoldenImage {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        if let instanceCapacity {
            try canvas3D.setInstanceCapacityForTesting(instanceCapacity)
        }
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
        renderer.onAfterDraw = { commandBuffer in
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
        renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
        renderer.onRecordFrame = { _ in
            context.beginRecordingFrame(time: 0, deltaTime: 0)
            draw(context)
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { encoder, _ in
            context.replayDeferredMain(encoder: encoder, time: 0)
        }
        renderer.useExternalRenderLoop = true
        if shadows { context.enableShadows(resolution: 512) }
        renderer.renderFrame()
        inspect?(canvas3D)
        return try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture, commandQueue: renderer.commandQueue)
    }

    private func pixel(_ image: GoldenImage, _ p: (x: Int, y: Int)) -> SIMD3<Int> {
        let i = (p.y * image.width + p.x) * 4
        return SIMD3(Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
    }

    /// 床 + その上に浮く箱。既定カメラは -z を向き y は下向きなので、
    /// `directionalLight(_, +y, _)` が「上から差す光」になる（y 下向き座標系）。
    ///
    /// - Parameters:
    ///   - material: 床を描く直前に呼ばれるマテリアル設定。
    ///   - casterFirst: `true` なら影を落とす箱を床より先に描く。描画順は絵を変えない
    ///     （深度で解決される）が、インスタンスバッチの消費順は変わるので、床を
    ///     イミディエイト経路へ落としたいときに使う（#391）。
    private func floorAndCaster(
        ambient: Float = 50,
        lightDirection: SIMD3<Float> = SIMD3(-0.35, 0.9, -0.5),
        casterFirst: Bool = false,
        material: @escaping (SketchContext) -> Void = { _ in }
    ) -> (SketchContext) -> Void {
        return { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.ambientLight(ambient)
            c.directionalLight(lightDirection.x, lightDirection.y, lightDirection.z)
            c.specular(0)
            c.noStroke()
            material(c)
            c.fill(Color(r: 0.8, g: 0.8, b: 0.8))

            let floor = {
                c.pushMatrix()
                c.translate(64, 96, 0)
                c.box(120, 4, 120)         // 影を受ける床
                c.popMatrix()
            }
            let caster = {
                c.pushMatrix()
                c.translate(64, 56, 0)
                c.box(30)                  // 影を落とす箱
                c.popMatrix()
            }

            if casterFirst {
                caster()
                floor()
            } else {
                floor()
                caster()
            }
        }
    }

    // MARK: - ambient

    @Test("影の中でも ambient は残る（影の減衰は直接光のみ）")
    func ambientSurvivesShadow() throws {
        let image = try render(shadows: true, draw: floorAndCaster(ambient: 50))
        let shadowed = pixel(image, Self.shadowedFloor)
        let lit = pixel(image, Self.litFloor)

        // ambientLight(50) は colorMode(RGB, 255) 基準なので 50/255。床の基色は 0.8。
        let expected = Int((50.0 / 255.0 * 0.8 * 255.0).rounded())  // = 40
        #expect(
            abs(shadowed.x - expected) <= 2,
            "影の中の輝度が ambient と一致しない: \(shadowed) / 期待 \(expected)")
        #expect(shadowed.x < lit.x - 20, "影が落ちていない（影の内外で差がない）")
    }

    @Test("ambient を上げると影領域の輝度が追従する")
    func shadowBrightnessTracksAmbient() throws {
        var measured: [(Float, Int)] = []
        for ambient: Float in [30, 90, 200] {
            let image = try render(shadows: true, draw: floorAndCaster(ambient: ambient))
            measured.append((ambient, pixel(image, Self.shadowedFloor).x))
        }
        for (ambient, value) in measured {
            let expected = Int((ambient / 255.0 * 0.8 * 255.0).rounded())
            #expect(
                abs(value - expected) <= 2,
                "ambient=\(ambient) の影領域が \(value)（期待 \(expected)）")
        }
        #expect(measured[0].1 < measured[1].1 && measured[1].1 < measured[2].1)
    }

    // MARK: - emissive

    @Test("影の中でも emissive は残る（Blinn-Phong）")
    func emissiveSurvivesShadowBlinnPhong() throws {
        let image = try render(
            shadows: true,
            draw: floorAndCaster(material: { c in
                c.pbr(false)
                c.emissive(Color(r: 0, g: 0.6, b: 0))
            }))
        let shadowed = pixel(image, Self.shadowedFloor)
        // ambient(40) + emissive 0.6 → G は 40 + 153 = 193 付近。
        #expect(
            shadowed.y >= 180,
            "影の中で emissive が失われた: \(shadowed)")
        #expect(shadowed.y > shadowed.x + 100, "emissive の色が影で潰れている: \(shadowed)")
    }

    @Test("影の中でも emissive は残る（PBR）")
    func emissiveSurvivesShadowPBR() throws {
        let image = try render(
            shadows: true,
            draw: floorAndCaster(material: { c in
                c.pbr(true)
                c.roughness(0.5)
                c.metallic(0)
                c.emissive(Color(r: 0, g: 0.6, b: 0))
            }))
        let shadowed = pixel(image, Self.shadowedFloor)
        #expect(shadowed.y >= 180, "影の中で emissive が失われた: \(shadowed)")
        #expect(shadowed.y > shadowed.x + 100, "emissive の色が影で潰れている: \(shadowed)")
    }

    // MARK: - ambient occlusion

    @Test("ambient occlusion は影の中でも ambient に効く（PBR）")
    func ambientOcclusionAppliesInShadow() throws {
        func shadowedValue(ao: Float) throws -> Int {
            let image = try render(
                shadows: true,
                draw: floorAndCaster(material: { c in
                    c.pbr(true)
                    c.roughness(0.5)
                    c.metallic(0)
                    c.ambientOcclusion(ao)
                }))
            return pixel(image, Self.shadowedFloor).x
        }
        let full = try shadowedValue(ao: 1.0)
        let occluded = try shadowedValue(ao: 0.2)

        // ao=0.2 なら影の中の ambient も 1/5 になる（= 40 * 0.2 ≒ 8）。
        let expected = Int((50.0 / 255.0 * 0.8 * 0.2 * 255.0).rounded())
        #expect(
            abs(occluded - expected) <= 3,
            "影の中で ambient occlusion が無視されている: \(occluded) / 期待 \(expected)")
        #expect(occluded < full - 20, "ao を下げても影領域が暗くならない")
    }

    // MARK: - 非インスタンス（イミディエイト）経路（Issue #391）

    /// `drawMesh()` はインスタンスバッファが満杯だと非インスタンス経路へ落ちる。
    /// この経路は `buffer(5)` / `texture(1)` にシャドウリソースをバインドしていたのに
    /// 組み込みフラグメントシェーダーが引数として受け取っておらず、影を無視していた。
    /// 「同じシーンなのにこのメッシュだけ影が落ちない」という原因の分かりにくい
    /// 見た目のズレになるので、インスタンス経路と同じ絵になることを画素で固定する。
    @Test("インスタンスバッファ満杯でフォールバックしても影が落ちる")
    func immediatePathReceivesShadow() throws {
        // 箱 → 床の順に描き、容量 1 のバッチを箱で使い切らせて床を落とす。
        let scene = floorAndCaster(casterFirst: true)
        let instanced = try render(shadows: true, draw: scene)

        var immediateDraws = 0
        let immediate = try render(
            shadows: true, instanceCapacity: 1,
            inspect: { immediateDraws = $0.immediateDrawCountForTesting },
            draw: scene)

        #expect(immediateDraws >= 1, "フォールバックが起きておらずテストが素通りしている")

        let shadowed = pixel(immediate, Self.shadowedFloor)
        let lit = pixel(immediate, Self.litFloor)
        let expected = Int((50.0 / 255.0 * 0.8 * 255.0).rounded())  // ambient のみ = 40
        #expect(
            abs(shadowed.x - expected) <= 2,
            "イミディエイト経路の影の中が ambient と一致しない: \(shadowed) / 期待 \(expected)")
        #expect(shadowed.x < lit.x - 20, "イミディエイト経路に影が落ちていない")

        // 経路が違っても絵は同じであること（フォールバックは最適化の有無でしかない）。
        var maxDiff = 0
        for i in 0..<instanced.rgba.count {
            maxDiff = max(maxDiff, abs(Int(instanced.rgba[i]) - Int(immediate.rgba[i])))
        }
        #expect(maxDiff <= 2, "インスタンス経路と絵が食い違う（最大差 \(maxDiff)）")
    }

    // MARK: - ライト方向の規約（Issue #364 の症状 2）

    /// #364 は「真上寄りの平行光でシーン全体が影判定になる」と報告したが、
    /// 実体は **y 下向き座標系**での方向指定の取り違えだった。
    /// `directionalLight(0, -1, 0)` は「上を向いて進む光」= 床の下から差す光なので、
    /// 床が箱を正しく遮蔽する。上から差すのは `directionalLight(0, +1, 0)`。
    ///
    /// この規約が反転すると影を使うスケッチが全滅するため、画素で固定しておく。
    @Test("真上からの平行光でシーン全体が影にならない")
    func overheadLightDoesNotShadowEverything() throws {
        // #364 の `directionalLight(-0.35, -0.9, -0.5)` と同じ傾きで、符号だけ正した向き。
        let scene = floorAndCaster(lightDirection: SIMD3(-0.35, 0.9, -0.5))
        let withoutShadows = try render(shadows: false, draw: scene)
        let withShadows = try render(shadows: true, draw: scene)

        // 影を落とす箱（シーンの最上位にあり遮蔽物がない）は影オンでも変わらず、
        // かつ ambient より明るい = 直接光が届いている。
        let casterTop = (x: 64, y: 45)
        let ambientOnly = Int((50.0 / 255.0 * 0.8 * 255.0).rounded())
        #expect(
            pixel(withShadows, casterTop) == pixel(withoutShadows, casterTop),
            "遮蔽物のない面が影判定になっている")
        #expect(
            pixel(withShadows, casterTop).x > ambientOnly + 20,
            "遮蔽物のない面が ambient だけになっている: \(pixel(withShadows, casterTop))")

        // 床の影は箱の真下だけ。ジオメトリ画素の大半は影オンでも変化しないこと。
        var geometryPixels = 0
        var darkened = 0
        for i in stride(from: 0, to: withoutShadows.rgba.count, by: 4) {
            let before = Int(withoutShadows.rgba[i]) + Int(withoutShadows.rgba[i + 1])
                + Int(withoutShadows.rgba[i + 2])
            let after = Int(withShadows.rgba[i]) + Int(withShadows.rgba[i + 1])
                + Int(withShadows.rgba[i + 2])
            guard before > 30 else { continue }  // 背景（黒）を除く
            geometryPixels += 1
            if after < before - 6 { darkened += 1 }
        }
        #expect(geometryPixels > 1000, "シーンが描けていない")
        let ratio = Double(darkened) / Double(geometryPixels)
        #expect(ratio > 0.01, "影がまったく落ちていない（\(ratio)）")
        #expect(ratio < 0.35, "シーンのほぼ全体が影判定になっている（\(ratio)）")
    }
}
