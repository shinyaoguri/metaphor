import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// 環境（IBL / skybox）の状態と絵を固定する（Epic #293 G3b・Issue #710）。
///
/// 「金属に見えるか」は画像を読まないと判定できないが、**壊れているか**は数値で足切り
/// できる。ここでは「環境なしでは metallic を上げると輝度の分散が消えてフラットに潰れる」
/// 「環境ありでは潰れない」という差を固定し、退行したら赤くする。
@Suite("Environment (IBL / skybox)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct EnvironmentIBLTests {

    private static let size = 128

    // MARK: - 状態

    @Test("environment() は強度を Material3D へ載せ、トーンマップを acesFilmic へ昇格させる")
    func environmentSetsIntensityAndPromotesToneMapping() throws {
        let canvas3D = try Self.makeCanvas3D()

        #expect(canvas3D.toneMapParams.z == 0)
        #expect(canvas3D.toneMapParams.x == Float(ToneMapMode.none.rawValue))

        canvas3D.environment(.studio, intensity: 0.8)

        #expect(canvas3D.environment != nil)
        #expect(canvas3D.toneMapParams.z == 0.8)
        #expect(canvas3D.currentMaterial.toneMapParams.z == 0.8)
        // 環境を入れると輝度は 1.0 を超えるので、未指定なら ACES へ自動昇格する
        #expect(canvas3D.toneMapParams.x == Float(ToneMapMode.acesFilmic.rawValue))
    }

    @Test("toneMapping() を明示していれば environment() は上書きしない")
    func explicitToneMappingWins() throws {
        let canvas3D = try Self.makeCanvas3D()

        canvas3D.toneMapping(.reinhard)
        canvas3D.environment(.sunset)

        #expect(canvas3D.toneMapParams.x == Float(ToneMapMode.reinhard.rawValue))
    }

    @Test("environment() は既定アンビエントを 0 にし、ambientLight() の明示は残す")
    func environmentSuppressesOnlyDefaultAmbient() throws {
        let implicit = try Self.makeCanvas3D()
        implicit.environment(.studio)
        #expect(implicit.currentMaterial.ambientColor.x == 0)

        let explicit = try Self.makeCanvas3D()
        explicit.ambientLight(80)
        let ambientBefore = explicit.currentMaterial.ambientColor
        explicit.environment(.studio)
        #expect(explicit.currentMaterial.ambientColor == ambientBefore)
    }

    @Test("noEnvironment() で環境が外れ、既定アンビエントが戻る")
    func noEnvironmentRestoresDefaults() throws {
        let canvas3D = try Self.makeCanvas3D()

        canvas3D.environment(.overcast)
        canvas3D.noEnvironment()

        #expect(canvas3D.environment == nil)
        #expect(canvas3D.toneMapParams.z == 0)
        #expect(canvas3D.currentMaterial.toneMapParams.z == 0)
        #expect(canvas3D.currentMaterial.ambientColor.x > 0)
    }

    @Test("同じプリセットの環境はベイクし直さず使い回される")
    func environmentIsCachedPerPreset() throws {
        let canvas3D = try Self.makeCanvas3D()

        canvas3D.environment(.studio)
        let first = canvas3D.environment
        canvas3D.noEnvironment()
        canvas3D.environment(.studio)

        #expect(first != nil)
        #expect(canvas3D.environment === first)
    }

    @Test("プリセットは 3 種とも焼ける", arguments: EnvironmentPreset.allCases)
    func allPresetsBake(preset: EnvironmentPreset) throws {
        let canvas3D = try Self.makeCanvas3D()

        canvas3D.environment(preset)

        let environment = try #require(canvas3D.environment)
        #expect(environment.irradianceTexture.textureType == .typeCube)
        #expect(environment.prefilteredTexture.textureType == .typeCube)
        // roughness → mip の対応が成り立つには複数 mip が要る
        #expect(environment.prefilteredTexture.mipmapLevelCount > 1)
    }

    // MARK: - 絵

    @Test("環境なしの metallic はフラットに潰れ、環境ありでは階調が残る")
    func environmentKeepsMetallicFromCollapsing() throws {
        let without = try Self.renderMetallicSphere(preset: nil)
        let with = try Self.renderMetallicSphere(preset: .studio)

        let spreadWithout = Self.luminanceSpread(without, region: Self.sphereRegion)
        let spreadWith = Self.luminanceSpread(with, region: Self.sphereRegion)

        // #414 の 2 本目が踏んだ「特徴のない灰色の塊」を数値で足切りする。
        // 環境があれば、同じ metallic でも面ごとに違う環境を映して階調が出る。
        #expect(spreadWith > spreadWithout * 2)
    }

    @Test("skybox は背景を塗るが、3D シェイプの手前には出ない")
    func skyboxFillsBackgroundButNotForeground() throws {
        let withSkybox = try Self.renderMetallicSphere(preset: .studio)
        let iblOnly = try Self.renderMetallicSphere(preset: .studio, background: false)

        // 隅は球が無いので背景。skybox 有無で色が変わる
        let corner = (x: 4, y: 4)
        #expect(Self.pixel(withSkybox, corner) != Self.pixel(iblOnly, corner))
        // background: false なら背景は background() の黒のまま
        #expect(Self.luminance(Self.pixel(iblOnly, corner)) < 0.02)

        // 球の中心は skybox に覆われていない（覆われていれば背景と同じ色になる）
        let center = (x: Self.size / 2, y: Self.size / 2)
        #expect(Self.pixel(withSkybox, center) != Self.pixel(withSkybox, corner))
    }

    @Test("skybox より後に描いた 2D は前景として残る")
    func foreground2DSurvivesSkybox() throws {
        let image = try OffscreenSketchHarness.render(size: Self.size) { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.environment(.sunset)
            Self.metallicSphere(c)
            // 3D の後に描く 2D は最前面に残る
            c.fill(Color(r: 1, g: 0, b: 0))
            c.noStroke()
            c.rect(0, 0, 16, 16)
        }

        let p = Self.pixel(image, (x: 4, y: 4))
        #expect(p.x > 200 && p.y < 60 && p.z < 60)
    }

    @Test("Graphics3D（MSAA なし）でも環境が使える")
    func environmentWorksOnGraphics3D() throws {
        let graphics = try Graphics3D(
            device: #require(MetalTestHelper.device),
            commandQueue: #require(MetalTestHelper.commandQueue()),
            shaderLibrary: MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: Self.size,
            height: Self.size
        )

        graphics.beginDraw()
        graphics.environment(.studio)
        graphics.directionalLight(-0.4, 0.6, -1)
        graphics.noStroke()
        graphics.metallic(0.9)
        graphics.roughness(0.25)
        graphics.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        graphics.sphere(40)
        graphics.endDraw(wait: true)

        // MSAA サンプル数がメインパス（4）と違っても skybox のパイプラインが作れて、
        // 何かが描かれていること（真っ黒でない）を見る
        let image = try GoldenImage.readback(
            texture: graphics.texture, commandQueue: #require(MetalTestHelper.commandQueue()))
        var lit = false
        for y in 0..<image.height where !lit {
            for x in 0..<image.width where Self.luminance(Self.pixel(image, (x: x, y: y))) > 0.05 {
                lit = true
                break
            }
        }
        #expect(lit)
    }

    // MARK: - ヘルパー

    private static func makeCanvas3D() throws -> Canvas3D {
        let renderer = try MetaphorRenderer(width: size, height: size)
        return try Canvas3D(renderer: renderer)
    }

    /// 球が写る領域（画面中央のまわり）。
    private static let sphereRegion = (x: 44, y: 44, width: 40, height: 40)

    private static func metallicSphere(_ c: SketchContext) {
        c.directionalLight(-0.4, 0.6, -1)
        c.noStroke()
        c.fill(Color(r: 0.85, g: 0.85, b: 0.88))
        c.metallic(0.72)
        c.roughness(0.28)
        c.pushMatrix()
        c.translate(Float(size) / 2, Float(size) / 2, 0)
        c.sphere(40)
        c.popMatrix()
    }

    private static func renderMetallicSphere(
        preset: EnvironmentPreset?,
        background: Bool = true
    ) throws -> GoldenImage {
        try OffscreenSketchHarness.render(size: size) { c in
            c.background(Color(r: 0, g: 0, b: 0))
            if let preset {
                c.environment(preset, background: background)
            } else {
                // 環境なしの側もトーンマップは揃えて、比較を「環境の有無」だけにする
                c.toneMapping(.acesFilmic)
            }
            metallicSphere(c)
        }
    }

    private static func pixel(_ image: GoldenImage, _ p: (x: Int, y: Int)) -> SIMD3<Int> {
        let i = (p.y * image.width + p.x) * 4
        return SIMD3(Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
    }

    private static func luminance(_ p: SIMD3<Int>) -> Double {
        (0.2126 * Double(p.x) + 0.7152 * Double(p.y) + 0.0722 * Double(p.z)) / 255.0
    }

    /// 指定領域の輝度の標準偏差。「フラットな塊」かどうかの判定に使う。
    private static func luminanceSpread(
        _ image: GoldenImage,
        region: (x: Int, y: Int, width: Int, height: Int)
    ) -> Double {
        var values: [Double] = []
        values.reserveCapacity(region.width * region.height)
        for y in region.y..<(region.y + region.height) {
            for x in region.x..<(region.x + region.width) {
                values.append(luminance(pixel(image, (x: x, y: y))))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
