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
