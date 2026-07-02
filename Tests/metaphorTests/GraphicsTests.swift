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
