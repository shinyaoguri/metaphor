import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - ブレンドモードが結果のアルファに与える影響（#800）

/// `blendMode()` は**色の混ぜ方**を選ぶもので、描いた領域の不透明度を削るものではない。
/// 以前は `.subtract` だけが `alphaBlendOperation = .reverseSubtract` で、
/// 不透明な src を不透明な dst に重ねると `1 - 1 = 0` になりキャンバスに穴が開いていた。
@Suite("BlendMode result alpha", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct BlendModeAlphaTests {

    private func makeGraphics(width: Int = 32, height: Int = 32) throws -> Graphics {
        try Graphics(
            device: MetalTestHelper.device!,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: width,
            height: height
        )
    }

    /// 下地を 1 枚敷き、その上に `mode` で src を重ねて中心画素を読む。
    private func compose(
        dst: Color,
        src: Color,
        mode: BlendMode,
        in pg: Graphics
    ) -> Color {
        pg.beginDraw()
        pg.noStroke()
        pg.blendMode(.opaque)
        pg.fill(dst)
        pg.rect(0, 0, 32, 32)

        pg.blendMode(mode)
        pg.fill(src)
        pg.rect(0, 0, 32, 32)
        pg.blendMode(.alpha)
        pg.endDraw(wait: true)

        let img = pg.toImage()
        img.loadPixels()
        return img.get(16, 16)
    }

    /// 不透明どうしを重ねたら、どのモードでも結果は不透明。
    @Test("every mode keeps the area opaque when both src and dst are opaque")
    func opaqueOverOpaqueStaysOpaque() throws {
        let dst = Color(r: 0.2, g: 0.4, b: 0.6)
        let src = Color(r: 0.5, g: 0.25, b: 0.1)

        for mode in BlendMode.allCases {
            let pg = try makeGraphics()
            let result = compose(dst: dst, src: src, mode: mode, in: pg)
            #expect(result.a > 0.99,
                    "\(mode) が不透明な領域のアルファを削っている (got \(result.a)) — #800")
        }
    }

    /// `.subtract` が引くのは色であって不透明度ではない。
    ///
    /// #800 の時点では「下地の α をそのまま残す」を選んでいたが、ADR-0012 で
    /// **どのモードも結果 α は over（`src.a + dst.a·(1 − src.a)`）**に揃えた。
    /// 塗った領域の不透明度を削らないという #800 の原則はそのままで（over は α を
    /// 減算しない）、変わるのは「半透明な下地へ不透明な src を重ねたとき」だけ。
    @Test("subtract composites the result alpha like every other mode")
    func subtractUsesOverForResultAlpha() throws {
        let pg = try makeGraphics()
        let result = compose(
            dst: Color(r: 0.6, g: 0.6, b: 0.6, alpha: 0.5),
            src: Color(r: 0.25, g: 0.25, b: 0.25),
            mode: .subtract,
            in: pg
        )
        // 旧実装は 0.5 - 1.0 = 0（穴が開く）、#800 の手当てでは 0.5 のままだった
        #expect(abs(result.a - 1.0) < 0.02,
                "不透明な src を重ねたら結果も不透明 (got \(result.a)) — ADR-0012")
    }

    /// RGB 側は従来どおり `dst - src`（#800 で変えていないことの固定）。
    @Test("subtract still subtracts the color channels")
    func subtractStillSubtractsColor() throws {
        let pg = try makeGraphics()
        let result = compose(
            dst: Color(r: 0.2, g: 0.4, b: 0.6),
            src: Color(r: 0.5, g: 0.25, b: 0.1),
            mode: .subtract,
            in: pg
        )
        expectApproxEqual(result.r, 0.0, epsilon: 0.02)
        expectApproxEqual(result.g, 0.15, epsilon: 0.02)
        expectApproxEqual(result.b, 0.5, epsilon: 0.02)
    }
}
