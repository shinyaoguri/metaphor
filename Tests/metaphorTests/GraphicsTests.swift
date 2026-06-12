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
