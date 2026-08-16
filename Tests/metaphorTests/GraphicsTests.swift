import Testing
import Metal
import simd
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

// MARK: - 2D 描画 API の転送（#908）

// `Graphics` は `Canvas2D` / `SketchContext` の 2D API を転送しきれておらず、
// コンター・クリップ・グラデーション・行間・アウトライン・変換・変換/スタイルの
// 個別スタックの 18 本が、オフスクリーンへ描くときだけ使えなかった。
// ここでは「呼べるか」ではなく「効いた結果が出るか」（ピクセル・座標・輪郭）で見る。

@Suite("Graphics 2D API parity", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GraphicsAPIParityTests {

    private func makeGraphics(width: Int = 32, height: Int = 32) throws -> Graphics {
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

    /// 黒い下地に `body` を描いて、結果を読める `MImage` を返す。
    private func render(_ pg: Graphics, _ body: (Graphics) -> Void) -> MImage {
        pg.beginDraw()
        pg.background(Color(r: 0, g: 0, b: 0))
        pg.noStroke()
        body(pg)
        pg.endDraw(wait: true)
        let img = pg.toImage()
        img.loadPixels()
        return img
    }

    /// 絵を見ない検査用。変換とスタックは `beginDraw()` ごとに始まるので、
    /// 状態を見る呼び出しは必ず 1 パスの内側で行う。
    private func inDraw(_ pg: Graphics, _ body: (Graphics) -> Void) {
        pg.beginDraw()
        body(pg)
        pg.endDraw()
    }

    /// 点群の y 方向の広がり（空なら 0）。
    private func ySpan(_ points: [Vec2]) -> Float {
        guard let lo = points.map(\.y).min(), let hi = points.map(\.y).max() else { return 0 }
        return hi - lo
    }

    // MARK: - クリップ

    // 回帰(#908): 転送が届かなければ（no-op なら）シザーが設定されず全面が白くなる。
    @Test("beginClip がクリップ矩形の外を切り落とす")
    func beginClipIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.beginClip(0, 0, 16, 32)   // 左半分だけ描けるようにする
            $0.rect(0, 0, 32, 32)        // 全面を塗ろうとする
        }
        #expect(img.get(8, 16).r > 0.9, "クリップ内（左半分）は塗られる")
        #expect(img.get(24, 16).r < 0.1,
                "クリップ外（右半分）が塗られている: beginClip が canvas へ届いていない(#908)")
    }

    // 「クリップ中は落ちる」「解除後は描ける」の両方を 1 枚で見る。片方だけだと
    // beginClip / endClip がそろって no-op のときに素通りしてしまう。
    @Test("endClip で前のクリップ領域へ戻る")
    func endClipIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.beginClip(0, 0, 16, 32)
            $0.rect(0, 0, 32, 32)        // 白は左半分にしか出ない
            $0.endClip()
            $0.fill(Color(r: 1, g: 0, b: 0))
            $0.rect(16, 0, 8, 32)        // 解除後は x = 16..24 へ描ける
        }
        let left = img.get(8, 16)
        #expect(left.r > 0.9 && left.g > 0.9, "クリップ内は白 (got \(left))")
        let released = img.get(20, 16)
        #expect(released.r > 0.9 && released.g < 0.1,
                "endClip 後の赤が出ていない (got \(released))")
        #expect(img.get(28, 16).r < 0.1,
                "どちらも描いていない領域が白い: クリップが効いていない(#908)")
    }

    // 境界値: キャンバス外の矩形は空のシザーへ潰れる（範囲外のシザー矩形は Metal の
    // validation で落ちるため、潰し損ねると「描かれない」ではなくクラッシュになる）。
    @Test("キャンバス外のクリップ矩形では 1 ピクセルも描かれない")
    func clipFullyOutsideCanvas() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.beginClip(100, 100, 50, 50)
            $0.rect(0, 0, 32, 32)
        }
        #expect(img.get(16, 16).r < 0.1, "キャンバス外のクリップなら何も描かれない")
    }

    // 境界値: 負の原点は幅・高さも削って左上へクランプされる（-20 + 30 = 10 まで）。
    @Test("負の原点のクリップ矩形は左上へクランプされる")
    func clipNegativeOrigin() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.beginClip(-20, -20, 30, 30)
            $0.rect(0, 0, 32, 32)
        }
        #expect(img.get(4, 4).r > 0.9, "クランプ後の 10x10 は塗られる")
        #expect(img.get(16, 16).r < 0.1, "クランプ後の領域の外は塗られない")
    }

    // MARK: - コンター（穴）

    @Test("beginContour / endContour がシェイプに穴を開ける")
    func contourIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.beginShape()
            $0.vertex(2, 2); $0.vertex(30, 2); $0.vertex(30, 30); $0.vertex(2, 30)
            $0.beginContour()
            $0.vertex(10, 10); $0.vertex(10, 22); $0.vertex(22, 22); $0.vertex(22, 10)
            $0.endContour()
            $0.endShape(.close)
        }
        #expect(img.get(5, 16).r > 0.9, "外周の内側（穴の外）は塗られる")
        #expect(img.get(16, 16).r < 0.1,
                "コンターの内側が塗られている: beginContour / endContour が canvas へ届いていない(#908)")
    }

    // 境界値: 頂点が 3 つ未満のコンターは捨てられる（穴にならない）。
    // 「穴にならない」だけを見ると転送が no-op でも素通りするので、
    // 同じ 1 枚に 3 頂点のコンター（= 穴になる）を並べて対照にする。
    @Test("頂点 2 つのコンターは穴にならず、3 つなら穴になる")
    func contourWithTooFewVertices() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.fill(Color(r: 1, g: 1, b: 1))
            // 左: 2 頂点のコンター（捨てられる）
            $0.beginShape()
            $0.vertex(1, 2); $0.vertex(15, 2); $0.vertex(15, 30); $0.vertex(1, 30)
            $0.beginContour()
            $0.vertex(4, 10); $0.vertex(12, 20)
            $0.endContour()
            $0.endShape(.close)
            // 右: 3 頂点のコンター（穴になる）
            $0.beginShape()
            $0.vertex(17, 2); $0.vertex(31, 2); $0.vertex(31, 30); $0.vertex(17, 30)
            $0.beginContour()
            $0.vertex(20, 10); $0.vertex(28, 10); $0.vertex(24, 22)
            $0.endContour()
            $0.endShape(.close)
        }
        #expect(img.get(8, 16).r > 0.9, "3 頂点未満のコンターは捨てられ、塗りは埋まったまま")
        #expect(img.get(18, 16).r > 0.9, "右のシェイプもコンターの外は塗られる")
        #expect(img.get(24, 14).r < 0.1,
                "3 頂点のコンターは穴になる: 塗られていれば contour が届いていない(#908)")
    }

    // MARK: - グラデーション

    @Test("linearGradient が既定（縦）方向に色を変える")
    func linearGradientIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.linearGradient(0, 0, 32, 32, Color(r: 0, g: 0, b: 0), Color(r: 1, g: 1, b: 1))
        }
        let top = img.get(16, 2).r
        let bottom = img.get(16, 29).r
        #expect(bottom - top > 0.7,
                "上端 \(top) → 下端 \(bottom): linearGradient が canvas へ届いていない(#908)")
    }

    // 名前付き引数まで届いているか（既定と違う軸を渡すと明るくなる向きが変わる）。
    @Test("linearGradient の axis が効く")
    func linearGradientAxisIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.linearGradient(0, 0, 32, 32, Color(r: 0, g: 0, b: 0), Color(r: 1, g: 1, b: 1),
                              axis: .horizontal)
        }
        let left = img.get(2, 16).r
        let right = img.get(29, 16).r
        #expect(right - left > 0.7, "左 \(left) → 右 \(right): axis: .horizontal が届いていない")
    }

    @Test("radialGradient が中心から外へ色を変える")
    func radialGradientIsForwarded() throws {
        let pg = try makeGraphics()
        let img = render(pg) {
            $0.radialGradient(16, 16, 15, Color(r: 1, g: 1, b: 1), Color(r: 0, g: 0, b: 0))
        }
        let center = img.get(16, 16).r
        let edge = img.get(16, 29).r   // 中心から 13px（半径 15 のほぼ外縁）
        #expect(center > 0.9, "中心は innerColor になる (got \(center))")
        #expect(center - edge > 0.7,
                "中心 \(center) → 外縁 \(edge): radialGradient が canvas へ届いていない(#908)")
    }

    // MARK: - 行間・テキストのアウトライン

    // `textLeading` と `textToContours` の 2 本を同時に見る（行送りは輪郭の
    // y 方向の広がりに現れる）。どちらの転送が no-op でも差が出なくなる。
    @Test("textLeading が複数行の送り量に効く")
    func textLeadingIsForwarded() throws {
        let pg = try makeGraphics(width: 128, height: 128)
        // アウトラインの形は書体に依存するので、システムに必ずある書体で固定する。
        pg.textFont("Helvetica")
        pg.textSize(16)   // textSize は行間を既定へ戻すので、textLeading は後に呼ぶ

        pg.textLeading(10)
        let tight = ySpan(pg.textToContours("H\nH", 0, 40).flatMap { $0 })
        pg.textLeading(40)
        let loose = ySpan(pg.textToContours("H\nH", 0, 40).flatMap { $0 })

        #expect(tight > 0, "実測 \(tight): 輪郭が取れていない")
        #expect(abs((loose - tight) - 30) < 1,
                "行間 10 → 40 で 2 行の高さは 30 増えるはず (実測 \(tight) → \(loose))")
    }

    @Test("textToPoints / textToContours がグリフのアウトラインを返す")
    func textOutlineIsForwarded() throws {
        let pg = try makeGraphics(width: 128, height: 128)
        pg.textFont("Helvetica")
        pg.textSize(48)

        let contours = pg.textToContours("o", 10, 60)
        let points = pg.textToPoints("o", 10, 60)
        #expect(contours.count == 2, "'o' は外周 + 穴の 2 輪郭 (実測 \(contours.count))")
        #expect(!points.isEmpty && points.count == contours.reduce(0) { $0 + $1.count },
                "textToPoints は輪郭を平らに繋いだもの (実測 \(points.count))")

        // 位置の意味は text() と同じ（原点はベースライン左端）。
        let xs = points.map(\.x)
        #expect((xs.min() ?? -1) >= 9, "左端がほぼ x = 10 (実測 \(xs.min() ?? -1))")
        #expect((xs.max() ?? .infinity) <= 10 + pg.textWidth("o") + 1,
                "右端が advance の範囲に収まる (実測 \(xs.max() ?? .infinity))")
    }

    // 境界値: 空文字は空の輪郭（行分割や advance の計算で落ちない）。
    // 「空が返る」だけだと転送が no-op でも素通りするので、同じ `Graphics` で
    // 中身のある文字列が空にならないことを対照に置く。
    @Test("空文字のアウトラインは空")
    func textOutlineOfEmptyString() throws {
        let pg = try makeGraphics()
        pg.textFont("Helvetica")
        pg.textSize(24)
        #expect(pg.textToContours("", 0, 0).isEmpty)
        #expect(pg.textToPoints("", 0, 0).isEmpty)
        #expect(!pg.textToContours("H", 0, 0).isEmpty, "対照: 中身があれば空にならない")
    }

    // MARK: - 変換

    // `screenPosition` を実際に描いた位置と突き合わせる。以降の変換テストは
    // `screenPosition` で判定するので、まずここでピクセルへ錨を打つ。
    @Test("screenPosition が変換後のバッファ座標を返す")
    func screenPositionIsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        let img = render(pg) {
            $0.translate(8, 8)
            reported = $0.screenPosition(0, 0)
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.rect(0, 0, 4, 4)
        }
        #expect(reported.x == 8 && reported.y == 8,
                "translate(8, 8) 後の原点は (8, 8) (実測 \(reported))")
        #expect(img.get(10, 10).r > 0.9, "報告された位置に実際に描かれている")
        #expect(img.get(4, 4).r < 0.1, "変換前の位置には描かれていない")
    }

    @Test("applyMatrix(float3x3) が現在の変換に乗る")
    func applyMatrix3x3IsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        inDraw(pg) {
            $0.translate(4, 0)
            $0.applyMatrix(float3x3(columns: (
                SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(6, 9, 1))))
            reported = $0.screenPosition(0, 0)
        }
        #expect(reported.x == 10 && reported.y == 9,
                "既存の変換へ合成される (実測 \(reported))")
    }

    @Test("applyMatrix(6 成分) が Processing 形式で乗る")
    func applyMatrix6IsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        inDraw(pg) {
            // x' = n00*x + n01*y + n02, y' = n10*x + n11*y + n12
            $0.applyMatrix(1, 0, 5, 0, 1, 7)
            reported = $0.screenPosition(0, 0)
        }
        #expect(reported.x == 5 && reported.y == 7,
                "成分は行優先で解釈される (実測 \(reported))")
    }

    // 単位行列は `screenPosition` の「壊れ方」（恒等写像）と区別が付かないので、
    // ここだけはピクセルでも見る。
    @Test("resetMatrix が積んだ変換を単位行列へ戻す")
    func resetMatrixIsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        let img = render(pg) {
            $0.translate(9, 9)
            $0.rotate(1)
            $0.resetMatrix()
            reported = $0.screenPosition(3, 4)
            $0.fill(Color(r: 1, g: 1, b: 1))
            $0.rect(0, 0, 6, 6)
        }
        #expect(reported.x == 3 && reported.y == 4,
                "変換が残っている: resetMatrix が canvas へ届いていない(#908) (実測 \(reported))")
        #expect(img.get(3, 3).r > 0.9, "変換を戻した位置（左上）に描かれる")
    }

    @Test("shearX が x 方向にせん断する")
    func shearXIsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        inDraw(pg) {
            $0.shearX(.pi / 4)   // x' = x + tan(45°) * y
            reported = $0.screenPosition(0, 10)
        }
        #expect(abs(reported.x - 10) < 0.01 && abs(reported.y - 10) < 0.01,
                "y = 10 の点が x へ 10 ずれるはず (実測 \(reported))")
    }

    @Test("shearY が y 方向にせん断する")
    func shearYIsForwarded() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        inDraw(pg) {
            $0.shearY(.pi / 4)   // y' = y + tan(45°) * x
            reported = $0.screenPosition(10, 0)
        }
        #expect(abs(reported.x - 10) < 0.01 && abs(reported.y - 10) < 0.01,
                "x = 10 の点が y へ 10 ずれるはず (実測 \(reported))")
    }

    // MARK: - 変換・スタイルの個別スタック

    // `push()` / `pop()` は両方まとめて積む。個別スタックの値は「片方だけ戻る」ことなので、
    // 戻る側と戻らない側を 1 本のテストで両方見る。
    @Test("popMatrix は変換だけ戻し、スタイルは戻さない")
    func matrixStackIsForwarded() throws {
        let pg = try makeGraphics()
        var afterPop = SIMD2<Float>(-1, -1)
        let img = render(pg) {
            $0.fill(Color(r: 0, g: 0, b: 1))
            $0.pushMatrix()
            $0.translate(10, 10)
            $0.fill(Color(r: 1, g: 0, b: 0))   // スタイルは積んでいない
            $0.popMatrix()
            afterPop = $0.screenPosition(0, 0)
            $0.rect(0, 0, 8, 8)
        }
        #expect(afterPop.x == 0 && afterPop.y == 0,
                "popMatrix で変換が戻る (実測 \(afterPop))")
        let c = img.get(4, 4)
        #expect(c.r > 0.9 && c.b < 0.1,
                "popMatrix はスタイルを戻さない = 赤のまま (got \(c))")
    }

    @Test("popStyle はスタイルだけ戻し、変換は戻さない")
    func styleStackIsForwarded() throws {
        let pg = try makeGraphics()
        var afterPop = SIMD2<Float>(-1, -1)
        let img = render(pg) {
            $0.fill(Color(r: 0, g: 0, b: 1))
            $0.pushStyle()
            $0.fill(Color(r: 1, g: 0, b: 0))
            $0.translate(10, 10)               // 変換は積んでいない
            $0.popStyle()
            afterPop = $0.screenPosition(0, 0)
            $0.rect(0, 0, 8, 8)
        }
        #expect(afterPop.x == 10 && afterPop.y == 10,
                "popStyle は変換を戻さない (実測 \(afterPop))")
        let c = img.get(14, 14)
        #expect(c.b > 0.9 && c.r < 0.1, "popStyle で fill が青へ戻る (got \(c))")
    }

    // 境界値: 空のスタックへの pop は何もしない（落ちないし、状態も動かさない）。
    @Test("空のスタックへの popMatrix / popStyle は無害")
    func popOnEmptyStackIsHarmless() throws {
        let pg = try makeGraphics()
        var reported = SIMD2<Float>(-1, -1)
        inDraw(pg) {
            $0.translate(6, 7)
            $0.popMatrix()
            $0.popStyle()
            reported = $0.screenPosition(0, 0)
        }
        #expect(reported.x == 6 && reported.y == 7,
                "空の pop で変換が壊れない (実測 \(reported))")
    }
}
