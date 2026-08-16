import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Graphics (createGraphics) offscreen buffer

@Suite("Graphics offscreen buffer", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GraphicsTests {

    private func makeGraphics(width: Int = 64, height: Int = 64) throws -> Graphics {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        return try Graphics(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height
        )
    }

    @Test("vertex buffer slots rotate across draw cycles (triple buffering)")
    func bufferSlotsRotate() throws {
        let pg = try makeGraphics()
        // 以前は毎フレーム スロット 0 を使い回し、GPU がまだ読んでいる
        // 共有頂点バッファを CPU が上書きしていた
        #expect(pg.nextBufferIndexForTesting == 0)
        pg.beginDraw(); pg.endDraw()
        #expect(pg.nextBufferIndexForTesting == 1)
        pg.beginDraw(); pg.endDraw()
        #expect(pg.nextBufferIndexForTesting == 2)
        pg.beginDraw(); pg.endDraw()
        #expect(pg.nextBufferIndexForTesting == 0)
    }

    @Test("consecutive draw cycles each render their own content")
    func multiCycleRendering() throws {
        let pg = try makeGraphics()
        let colors: [(Color, (Float, Float, Float))] = [
            (.red, (1, 0, 0)),
            (.green, (0, 1, 0)),
            (.blue, (0, 0, 1)),
            (.white, (1, 1, 1)),
        ]
        for (fill, expected) in colors {
            pg.beginDraw()
            pg.noStroke()
            pg.fill(fill)
            pg.rect(0, 0, 64, 64)
            pg.endDraw(wait: true)

            let img = pg.toImage()
            img.loadPixels()
            let c = img.get(32, 32)
            #expect(abs(c.r - expected.0) < 0.1 &&
                    abs(c.g - expected.1) < 0.1 &&
                    abs(c.b - expected.2) < 0.1,
                    "Cycle should render its own color: got (\(c.r), \(c.g), \(c.b)), expected \(expected)")
        }
    }

    @Test("unbalanced beginDraw calls do not deadlock the in-flight semaphore")
    func unbalancedBeginDrawDoesNotDeadlock() throws {
        let pg = try makeGraphics()
        // endDraw を挟まず 5 回 — セマフォ(3)が詰まれば 4 回目以降で永久ブロック
        for _ in 0..<5 {
            pg.beginDraw()
        }
        pg.endDraw()
    }
}

// MARK: - 曲線の設定の転送（#540）

// `Graphics` は `curve()` / `curveVertex()` / `bezier()` を canvas へ転送していたが、
// その形を決める `curveDetail()` / `curveTightness()` の転送が落ちていたため、
// オフスクリーンへ描くときだけ既定値（detail 20 / tightness 0）に固定されていた。

@Suite("Graphics curve settings", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GraphicsCurveSettingsTests {

    private static let size = 64

    private func makeGraphics() throws -> Graphics {
        let device = MetalTestHelper.device!
        return try Graphics(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: Self.size,
            height: Self.size
        )
    }

    /// p1 → p2 が y = 48 の水平線分になる 4 点を、既定の Catmull-Rom なら
    /// t = 0.5 で (32, 24) まで弓なりに持ち上がるハンドル付きで描く。
    ///
    /// - Parameter configure: `curve()` の前に曲線の設定を入れるフック。
    private func drawCurve(_ pg: Graphics, configure: (Graphics) -> Void) {
        pg.beginDraw()
        pg.background(Color(r: 0, g: 0, b: 0))
        pg.noFill()
        pg.stroke(Color(r: 1, g: 1, b: 1))
        pg.strokeWeight(3)
        configure(pg)
        pg.curve(12, 240, 12, 48, 52, 48, 52, 240)
        pg.endDraw(wait: true)
    }

    /// 描かれた曲線が縦に広がった行数。
    ///
    /// 画面の上下方向の取り方に依存しないよう、光った行の**広がり**だけを見る。
    /// 既定の Catmull-Rom は弓なりに膨らむので広く、tightness = 1 や detail = 1 では
    /// p1 → p2 の直線になるのでストローク幅ぶんしか広がらない。
    private func litRowSpan(_ pg: Graphics) -> Int {
        let img = pg.toImage()
        img.loadPixels()
        var minY = Int.max
        var maxY = Int.min
        for y in 0..<Self.size {
            for x in 0..<Self.size where img.get(x, y).r > 0.5 {
                minY = min(minY, y)
                maxY = max(maxY, y)
                break
            }
        }
        return minY <= maxY ? maxY - minY + 1 : 0
    }

    // 前提: 何も設定しなければ弓なりに膨らむ（下の 2 本の「潰れた」判定の対照）。
    @Test("既定では曲線は弓なりに膨らむ")
    func defaultCurveBulges() throws {
        let pg = try makeGraphics()
        drawCurve(pg) { _ in }
        let span = litRowSpan(pg)
        #expect(span > 15, "実測 \(span) 行: 膨らんでいないと以降の比較が成立しない")
    }

    // 回帰テスト(#540): 転送が無いと tightness は無視され、既定のまま膨らんだままになる。
    @Test("curveTightness(1) が効いて曲線が直線に潰れる")
    func curveTightnessIsForwarded() throws {
        let pg = try makeGraphics()
        drawCurve(pg) { $0.curveTightness(1) }
        let span = litRowSpan(pg)
        #expect(span < 10,
                "実測 \(span) 行: 弓なりのままなら curveTightness が canvas へ届いていない(#540)")
    }

    // 回帰テスト(#540): detail = 1 は p1 → p2 の 1 セグメント = 直線。
    @Test("curveDetail(1) が効いて曲線が 1 セグメントに潰れる")
    func curveDetailIsForwarded() throws {
        let pg = try makeGraphics()
        drawCurve(pg) { $0.curveDetail(1) }
        let span = litRowSpan(pg)
        #expect(span < 10,
                "実測 \(span) 行: 弓なりのままなら curveDetail が canvas へ届いていない(#540)")
    }

    // 境界値: Canvas2D 側は `max(1, n)` で 1 へ丸める。転送が値をいじらずそのまま渡すので、
    // 0 や負値でも 0 除算（t = i / 0）にならず detail = 1 と同じ直線になる。
    @Test("curveDetail の 0 以下は 1 に丸められる", arguments: [0, -3])
    func curveDetailClampsNonPositive(_ detail: Int) throws {
        let pg = try makeGraphics()
        drawCurve(pg) { $0.curveDetail(detail) }
        let span = litRowSpan(pg)
        #expect(span > 0, "実測 \(span) 行: 何も描かれていない（0 除算で頂点が壊れている）")
        #expect(span < 10, "実測 \(span) 行: detail = 1 と同じ直線になるべき")
    }
}

// MARK: - loadPixels の鮮度と順序保証（#158）

@Suite("Graphics loadPixels Freshness", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GraphicsLoadPixelsFreshnessTests {

    private func makeGraphics(width: Int = 16, height: Int = 16) throws -> Graphics {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        return try Graphics(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height
        )
    }

    @Test("draw then loadPixels immediately reads the latest content")
    func loadPixelsAfterEndDraw() throws {
        let pg = try makeGraphics()

        // 赤で塗って wait なしで終了 → 直後の loadPixels でも最新が読める
        // （リードバックが描画と同じキューに載るため commit 順序で保証される）
        pg.beginDraw()
        pg.background(Color(r: 1, g: 0, b: 0))
        pg.endDraw(wait: false)

        let img = pg.toImage()
        img.loadPixels()
        let red = img.get(8, 8)
        #expect(red.r > 0.9 && red.g < 0.1, "1 回目の描画結果が読める (got \(red))")

        // 再描画後も最新が読める（ラップテクスチャはピクセルキャッシュを信頼しない）
        pg.beginDraw()
        pg.background(Color(r: 0, g: 1, b: 0))
        pg.endDraw(wait: false)

        img.loadPixels()
        let green = img.get(8, 8)
        #expect(green.g > 0.9 && green.r < 0.1,
                "再描画後の loadPixels が古いキャッシュを返さない (got \(green))")
    }
}

// MARK: - 同一フレーム内の描き換え（#745）

@Suite("Graphics same-frame redraw", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GraphicsSameFrameRedrawTests {

    private func makeGraphics(width: Int = 16, height: Int = 16) throws -> Graphics {
        let device = MetalTestHelper.device!
        return try Graphics(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: MetalTestHelper.depthStencilCache(),
            width: width,
            height: height
        )
    }

    /// 1 枚の `Graphics` を同一フレーム内で描き換えて 2 回貼ると、
    /// **それぞれ貼った時点の内容**が出る（Processing と同じ）。
    ///
    /// 以前は `toImage()` がカラーテクスチャを参照するだけだったため、
    /// メインパスがフレーム末にまとめて実行される時点でテクスチャが最後の内容に
    /// なっており、両方が最後の色になっていた。
    @Test("same-frame redraw keeps the content each image() saw")
    func sameFrameRedrawKeepsEachSnapshot() throws {
        let fb = try OffscreenSketchHarness.render(size: 64) { ctx in
            guard let pg = ctx.createGraphics(32, 32) else { return }
            ctx.background(0)

            pg.beginDraw()
            pg.background(0, 0, 255)
            pg.endDraw()
            ctx.image(pg, 0, 0)

            pg.beginDraw()
            pg.background(0, 255, 0)
            pg.endDraw()
            ctx.image(pg, 32, 0)
        }

        func pixel(_ x: Int, _ y: Int) -> SIMD3<Int> {
            let i = (y * fb.width + x) * 4
            return SIMD3(Int(fb.rgba[i]), Int(fb.rgba[i + 1]), Int(fb.rgba[i + 2]))
        }

        let left = pixel(16, 16)
        let right = pixel(48, 16)
        #expect(left.z > 200 && left.y < 60,
                "先に貼った側は image() 時点の青のままであるべき (got \(left)) — #745")
        #expect(right.y > 200 && right.z < 60,
                "後に貼った側は緑 (got \(right))")
    }

    /// 貸し出し後にローテーションしても、`background()` を呼ばないフレームの
    /// 「前の内容を引き継ぐ」挙動は保たれる（書き込み先が変わるので中身をコピーする）。
    @Test("content carries over across a rotation when background() is omitted")
    func contentIsPreservedAcrossRotation() throws {
        let pg = try makeGraphics()

        // 1 パス目: 赤で塗る → 2 パス目は loadAction = .clear（赤）で始まる
        pg.beginDraw()
        pg.background(Color(r: 1, g: 0, b: 0))
        pg.endDraw(wait: true)

        // 2 パス目: background() を呼ばない → 3 パス目は loadAction = .load になる
        pg.beginDraw()
        pg.endDraw(wait: true)

        // ここで外へ出す（= 次の beginDraw でローテーションが起きる）
        _ = pg.toImage()

        // 3 パス目: 前の内容（赤）の上に青い矩形を重ねる
        pg.beginDraw()
        pg.noStroke()
        pg.fill(Color(r: 0, g: 0, b: 1))
        pg.rect(0, 0, 8, 8)
        pg.endDraw(wait: true)

        let img = pg.toImage()
        img.loadPixels()
        let inside = img.get(4, 4)
        let outside = img.get(12, 12)
        #expect(inside.b > 0.9 && inside.r < 0.1, "重ねた矩形が出る (got \(inside))")
        #expect(outside.r > 0.9 && outside.b < 0.1,
                "ローテーションを跨いでも前の内容が引き継がれる (got \(outside))")
    }

    /// 描き換えなければテクスチャは入れ替わらない（無駄な確保をしない）。
    @Test("no rotation happens while the buffer is not redrawn")
    func repeatedToImageKeepsSameTexture() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.background(Color(r: 1, g: 0, b: 0))
        pg.endDraw(wait: true)

        let first = pg.toImage().texture
        let second = pg.toImage().texture
        #expect(first === second, "貸し出しだけではローテーションしない")

        pg.beginDraw()
        pg.endDraw(wait: true)
        #expect(pg.texture !== first, "貸し出し後に描き直したら別のテクスチャへ回る")
    }

    /// 毎フレーム確保し続けず、メインパスが読み終えたテクスチャを使い回す。
    @Test("rotation reuses textures once the frames that read them are done")
    func rotationReusesTextures() throws {
        let pg = try makeGraphics()
        let clock = FrameClock()
        pg.wireShaderInputs {
            Canvas2DShaderInputs(time: 0, mouse: SIMD2<Float>(0, 0), frameCount: clock.frame)
        }

        var seen: Set<ObjectIdentifier> = []
        for _ in 0..<12 {
            pg.beginDraw()
            pg.background(Color(r: 0, g: 0, b: 0))
            pg.endDraw(wait: true)
            seen.insert(ObjectIdentifier(pg.toImage().texture))
            clock.frame += 1
        }

        // メインの in-flight は 3 フレームなので、現行 1 枚 + 手放した 3 枚で足りる
        #expect(seen.count <= 4,
                "フレームが進めばテクスチャは使い回される (distinct=\(seen.count))")
    }

    /// `wireShaderInputs` に渡すクロージャから見えるフレーム番号。
    private final class FrameClock {
        var frame: UInt32 = 0
    }
}
