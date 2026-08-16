import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - アルファ意味論（ADR-0012）

/// metaphor は「公開 API は straight alpha、内部は premultiplied alpha」という規範を採る。
/// ここはその規範が守られていることを画素で確かめる検査。α < 1 の合成は長らく
/// どのテストも見ていなかった（ゴールデン画像は不透明を強制している）ため、
/// #801 / #846 / #847 / #848 のような取り違えが同時に 4 箇所で生きていた。
@Suite("Alpha semantics", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct AlphaSemanticsTests {

    private static let size = 32

    private func makeGraphics() throws -> Graphics {
        try Graphics(
            device: MetalTestHelper.device!,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: Self.size,
            height: Self.size
        )
    }

    /// 中心画素を 0...255 の整数で読む（Issue の表と直接突き合わせるため）。
    private func center(_ pg: Graphics) -> (r: Int, g: Int, b: Int, a: Int) {
        let img = pg.toImage()
        img.loadPixels()
        let c = img.get(Self.size / 2, Self.size / 2)
        func q(_ v: Float) -> Int { Int((v * 255).rounded()) }
        return (q(c.r), q(c.g), q(c.b), q(c.a))
    }

    // MARK: - blendMode の α（#801）

    /// 下地を 1 枚敷き、その上に `mode` で src を重ねて中心画素を読む。
    private func compose(src: Color?, mode: BlendMode) throws -> (r: Int, g: Int, b: Int, a: Int) {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.noStroke()
        pg.blendMode(.opaque)
        pg.fill(Color(r: 0.40, g: 0.30, b: 0.20))   // 下地 rgb(102,77,51)
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        if let src {
            pg.blendMode(mode)
            pg.fill(src)
            pg.rect(0, 0, Float(Self.size), Float(Self.size))
        }
        pg.blendMode(.alpha)
        pg.endDraw(wait: true)
        return center(pg)
    }

    private static let srcColor = (r: Float(0.25), g: Float(0.55), b: Float(0.15))

    /// α = 0 は「まったく効かない」。どのモードでも下地のまま。
    ///
    /// 以前は `.multiply` / `.screen` / `.lightest` / `.darkest` が α を無視していたため、
    /// **完全に透明な色を重ねただけで下地が変わっていた**（#801）。
    @Test("alpha = 0 leaves the destination untouched", arguments: BlendMode.allCases)
    func zeroAlphaIsNoOp(mode: BlendMode) throws {
        guard mode != .opaque else { return }   // .opaque は α を見ない（置換）モード
        let got = try compose(
            src: Color(r: Self.srcColor.r, g: Self.srcColor.g, b: Self.srcColor.b, alpha: 0),
            mode: mode
        )
        #expect(got == (102, 77, 51, 255), "\(mode) が α=0 で下地を変えている: \(got) — #801")
    }

    /// α = 0.5 は「効きが半分」。期待値は `mix(dst, blend(src, dst), 0.5)`。
    ///
    /// 数値は Issue #801 の期待値の列をそのまま持ってきたもの（実装から導出していない）。
    @Test("alpha = 0.5 halves the effect of every mode")
    func halfAlphaHalvesTheEffect() throws {
        let expected: [(BlendMode, (r: Int, g: Int, b: Int, a: Int))] = [
            (.alpha, (83, 109, 45, 255)),
            (.additive, (134, 147, 70, 255)),
            (.multiply, (64, 60, 29, 255)),
            (.screen, (121, 126, 66, 255)),
            (.subtract, (70, 39, 32, 255)),
            (.lightest, (102, 109, 51, 255)),
            (.darkest, (83, 77, 45, 255)),
            (.difference, (70, 70, 32, 255)),
            (.exclusion, (108, 105, 62, 255)),
        ]
        for (mode, want) in expected {
            let got = try compose(
                src: Color(r: Self.srcColor.r, g: Self.srcColor.g, b: Self.srcColor.b, alpha: 0.5),
                mode: mode
            )
            // 8bit の丸めで ±1 はずれる
            #expect(abs(got.r - want.r) <= 1 && abs(got.g - want.g) <= 1
                    && abs(got.b - want.b) <= 1 && abs(got.a - want.a) <= 1,
                    "\(mode) の α=0.5: got \(got), want \(want) — #801")
        }
    }

    // MARK: - テクスチャ経路（#846 / #847）

    /// 半透明の文字は「下地と文字色の中点」で塗られる。
    ///
    /// グリフアトラスは premultiplied で焼かれているので、straight のまま合成すると
    /// **カバレッジが二乗され、`fill` の α も二重に掛かる**（#846）。完全に被覆された
    /// 画素なら、その誤りは「白に届かず暗い側へ寄る」形で出る。
    @Test("semi-transparent text lands halfway between the backdrop and the fill color")
    func semiTransparentTextIsNotDoubleMultiplied() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.blendMode(.opaque)
        pg.noStroke()
        pg.fill(Color(r: 0, g: 0, b: 0))
        pg.rect(0, 0, Float(Self.size), Float(Self.size))

        pg.blendMode(.alpha)
        pg.fill(Color(r: 1, g: 1, b: 1, alpha: 0.5))
        pg.textSize(48)
        // 中心が確実にグリフの内側に来るように大きく描く
        pg.text("█", 0, Float(Self.size))
        pg.endDraw(wait: true)

        let got = center(pg)
        // 完全被覆の画素は黒と白の中点。二重掛けだと 64 付近まで落ちる
        #expect(abs(got.r - 128) <= 6 && abs(got.g - 128) <= 6 && abs(got.b - 128) <= 6,
                "半透明の文字に α が二重に掛かっている: \(got) — #846")
    }

    /// 透明なオフスクリーンへ描いた半透明の色を戻しても、α は二重に掛からない。
    ///
    /// `createGraphics()` の中身は premultiplied。straight として貼ると
    /// **半透明部が下地方向へ沈む**（#847）。
    @Test("compositing a transparent offscreen back does not multiply alpha twice")
    func offscreenRoundTripIsNotDoubleMultiplied() throws {
        let layer = try makeGraphics()
        layer.beginDraw()
        // 半透明の画素を作るのに `.opaque`（= 合成せず値をそのまま書く）を使う
        // （`background(α<1)` でも作れるが、それは #829 の検査が別に見ている）。
        layer.blendMode(.opaque)
        layer.noStroke()
        layer.fill(Color(r: 1, g: 0, b: 0, alpha: 0.5))
        layer.rect(0, 0, Float(Self.size), Float(Self.size))
        layer.endDraw(wait: true)

        let pg = try makeGraphics()
        pg.beginDraw()
        pg.blendMode(.opaque)
        pg.noStroke()
        pg.fill(Color(r: 1, g: 1, b: 1))            // 白い下地
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        pg.blendMode(.alpha)
        pg.image(layer.toImage(), 0, 0, Float(Self.size), Float(Self.size))
        pg.endDraw(wait: true)

        let got = center(pg)
        // 白 + 赤 50% = rgb(255,128,128)。二重掛けだと緑と青がさらに落ちる
        #expect(got.r >= 250 && abs(got.g - 128) <= 6 && abs(got.b - 128) <= 6,
                "オフスクリーンの戻しで α が二重に掛かっている: \(got) — #847")
    }

    // MARK: - background は合成ではなく置き換え（#829）

    /// `background(α = 0)` は、呼んだそのフレームでキャンバスを透明にする。
    ///
    /// 背景がレンダーパスのクリアに乗らないとき（= 前フレームと違う色を指定した初回）は
    /// 全画面クワッドで塗る。これを通常の α ブレンドで描くと **α = 0 のクワッドは合成の
    /// 定義上まったく何もしない**ため、透明で塗り直せなかった（#829）。
    @Test("background(alpha = 0) empties the canvas in the frame it is called")
    func transparentBackgroundAppliesInTheSameFrame() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.background(Color(r: 1, g: 1, b: 1))
        pg.noStroke()
        pg.fill(Color(r: 1, g: 1, b: 1))
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        pg.endDraw(wait: true)
        #expect(center(pg) == (255, 255, 255, 255), "下地を作れていない")

        pg.beginDraw()
        pg.background(Color(r: 0, g: 0, b: 0, alpha: 0))
        pg.endDraw(wait: true)

        let got = center(pg)
        #expect(got == (0, 0, 0, 0), "background(α=0) が呼んだフレームに効いていない: \(got) — #829")
    }

    /// α < 1 の背景も「置き換え」。下地は残らず、指定した色と α がそのまま入る。
    @Test("background(alpha = 0.5) replaces the canvas instead of compositing onto it")
    func semiTransparentBackgroundReplacesTheCanvas() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.background(Color(r: 1, g: 1, b: 1))
        pg.endDraw(wait: true)

        pg.beginDraw()
        pg.background(Color(r: 1, g: 0, b: 0, alpha: 0.5))
        pg.endDraw(wait: true)

        // 置き換えなら赤の半透明。α ブレンドだと白が透けて (255,128,128,255) になる
        let got = center(pg)
        #expect(abs(got.r - 255) <= 1 && got.g <= 1 && got.b <= 1 && abs(got.a - 128) <= 1,
                "半透明の background が下地と合成されている: \(got) — #829")
    }

    /// フレーム途中の `background(α < 1)` も置き換え。先に描いた図形は残らない。
    ///
    /// この経路（`hasDrawnAnything == true`）はレンダーパスのクリアに逃がせないので、
    /// 必ずクワッドで塗る。透明で塗り直せることをここでも固定する。
    @Test("a mid-frame background(alpha = 0) erases what was already drawn")
    func midFrameTransparentBackgroundErasesTheFrame() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.noStroke()
        pg.fill(Color(r: 1, g: 1, b: 1))
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        pg.background(Color(r: 0, g: 0, b: 0, alpha: 0))
        pg.endDraw(wait: true)

        let got = center(pg)
        #expect(got == (0, 0, 0, 0),
                "フレーム途中の background(α=0) が先に描いた図形を消していない: \(got) — #829")
    }

    /// `blendMode()` は背景に効かない。背景は合成ではなく置き換えだから。
    @Test("background ignores the active blend mode")
    func backgroundIgnoresTheActiveBlendMode() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.noStroke()
        pg.fill(Color(r: 0.5, g: 0.5, b: 0.5))
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        pg.blendMode(.multiply)
        pg.background(Color(r: 0.5, g: 0.5, b: 0.5))
        pg.endDraw(wait: true)

        // 置き換えなら 128。乗算に乗ると 0.5 * 0.5 = 64 まで落ちる
        let got = center(pg)
        #expect(abs(got.r - 128) <= 1 && abs(got.g - 128) <= 1 && abs(got.b - 128) <= 1
                && got.a == 255,
                "background に blendMode が効いている: \(got) — #829")
    }

    // MARK: - ピクセルの読み書き（#848）

    /// 読んだ色をそのまま書き戻したら、絵は変わらない。
    ///
    /// テクスチャは premultiplied なので、割り戻さずに `Color` へ包むと
    /// `set(x, y, get(x, y))` が恒等でなくなる（半透明の画素が読むたびに暗くなる）。
    @Test("set(x, y, get(x, y)) is the identity on a semi-transparent pixel")
    func pixelRoundTripIsIdentity() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        // 半透明の画素を作るのに `.opaque` を使う理由は上と同じ。
        pg.blendMode(.opaque)
        pg.noStroke()
        pg.fill(Color(r: 0.2, g: 0.8, b: 0.4, alpha: 0.5))
        pg.rect(0, 0, Float(Self.size), Float(Self.size))
        pg.endDraw(wait: true)

        let img = pg.toImage()
        img.loadPixels()
        let before = img.get(Self.size / 2, Self.size / 2)
        img.set(Self.size / 2, Self.size / 2, before)
        img.updatePixels()
        img.loadPixels()
        let after = img.get(Self.size / 2, Self.size / 2)

        #expect(abs(before.r - after.r) < 0.02 && abs(before.g - after.g) < 0.02
                && abs(before.b - after.b) < 0.02 && abs(before.a - after.a) < 0.02,
                "set(get()) が恒等でない: \(before) → \(after) — #848")
        // 読んだ値そのものが straight であること（fill した色が返る）
        #expect(abs(before.r - 0.2) < 0.02 && abs(before.g - 0.8) < 0.02
                && abs(before.b - 0.4) < 0.02 && abs(before.a - 0.5) < 0.02,
                "get() が premultiplied のまま返している: \(before) — #848")
    }

    /// α = 1 は「そのモードの混ぜ方をそのまま当てる」。
    @Test("alpha = 1 applies the blend function as-is")
    func fullAlphaAppliesBlend() throws {
        let expected: [(BlendMode, (r: Int, g: Int, b: Int, a: Int))] = [
            (.alpha, (64, 140, 38, 255)),
            (.additive, (166, 217, 89, 255)),
            (.multiply, (26, 42, 8, 255)),
            (.screen, (140, 175, 82, 255)),
            (.subtract, (38, 0, 13, 255)),
            (.lightest, (102, 140, 51, 255)),
            (.darkest, (64, 77, 38, 255)),
            (.difference, (38, 63, 13, 255)),
            (.exclusion, (115, 133, 74, 255)),
        ]
        for (mode, want) in expected {
            let got = try compose(
                src: Color(r: Self.srcColor.r, g: Self.srcColor.g, b: Self.srcColor.b, alpha: 1),
                mode: mode
            )
            #expect(abs(got.r - want.r) <= 1 && abs(got.g - want.g) <= 1
                    && abs(got.b - want.b) <= 1 && abs(got.a - want.a) <= 1,
                    "\(mode) の α=1: got \(got), want \(want)")
        }
    }
}
