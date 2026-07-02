import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

/// メインキャンバス loadPixels() の readback（Processing 互換、#202）。
@Suite("Canvas loadPixels Readback", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CanvasPixelsTests {

    private func makeHarness(
        draw: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        return (renderer, context)
    }

    @Test("loadPixels reads back the rendered canvas content")
    func loadPixelsReadsCanvas() throws {
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 1, g: 0, b: 0))   // 赤で塗る
        }
        renderer.renderFrame()

        // フレーム確定後の loadPixels は描画内容（赤）を読み戻す
        // （旧実装は空のバッファを作るだけで、常に 0 が読めていた）
        ctx.loadPixels()
        let pb = try #require(ctx.pixelBuffer)
        let center = pb.pixels[32 * 64 + 32]
        let r = (center >> 16) & 0xFF
        let g = (center >> 8) & 0xFF
        #expect(r > 200 && g < 50, "loadPixels はキャンバスの赤を読み戻すべき: \(String(center, radix: 16))")
    }

    @Test("loadPixels then updatePixels round-trips content (feedback pattern)")
    func loadModifyUpdateRoundTrip() throws {
        var frameIndex = 0
        let (renderer, ctx) = try makeHarness { c in
            if frameIndex == 0 {
                // フレーム 1: 緑で塗る
                c.background(Color(r: 0, g: 1, b: 0))
            } else {
                // フレーム 2: 前フレームの内容を読み、左半分を青へ加工して描き戻す
                // （draw() 先頭の loadPixels = 前フレーム末尾の内容）
                c.loadPixels()
                if let pb = c.pixelBuffer {
                    for y in 0..<64 {
                        for x in 0..<32 {
                            pb.pixels[y * 64 + x] = 0xFF00_00FF  // 青
                        }
                    }
                }
                c.updatePixels()
            }
            frameIndex += 1
        }
        renderer.renderFrame()   // フレーム 1: 緑
        renderer.renderFrame()   // フレーム 2: 読み戻し + 加工 + 描き戻し

        ctx.loadPixels()
        let pb = try #require(ctx.pixelBuffer)
        let left = pb.pixels[32 * 64 + 8]     // 加工した左半分 → 青
        let right = pb.pixels[32 * 64 + 56]   // 未加工の右半分 → 前フレームの緑
        #expect((left & 0xFF) > 200 && ((left >> 8) & 0xFF) < 50,
                "左半分は加工後の青: \(String(left, radix: 16))")
        #expect(((right >> 8) & 0xFF) > 200,
                "右半分は読み戻された緑が保持される: \(String(right, radix: 16))")
    }

    @Test("loadPixels recreates the buffer when the canvas is resized")
    func loadPixelsResize() throws {
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 1))
        }
        renderer.renderFrame()
        ctx.loadPixels()
        #expect(ctx.pixelBuffer?.width == 64)

        renderer.resizeCanvas(width: 32, height: 32)
        ctx.rebuildCanvas(
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer)
        )
        ctx.loadPixels()
        #expect(ctx.pixelBuffer?.width == 32, "リサイズ後はバッファが作り直される")
    }
}
