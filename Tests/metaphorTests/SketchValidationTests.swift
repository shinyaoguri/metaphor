import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Sketch API 引数検証（#150）

@Suite("Sketch API Validation", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchAPIValidationTests {

    private func makeContext(width: Int = 64, height: Int = 64) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: width, height: height)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        return (renderer, context)
    }

    @Test("colorMode with zero or negative max keeps colors finite")
    func colorModeZeroMax() throws {
        let (_, ctx) = try makeContext()
        // 0 は無視され現在の最大値（255）が維持される
        ctx.colorMode(.rgb, 0)
        ctx.fill(128, 64, 32)
        let f = ctx.canvas.fillColor
        #expect(f.x.isFinite && f.y.isFinite && f.z.isFinite && f.w.isFinite)
        #expect(abs(f.x - 128.0 / 255.0) < 0.01, "無効な max は無視され 255 レンジのまま: \(f)")

        // 負値・NaN も無視される
        ctx.colorMode(.rgb, -10, 0, Float.nan, 255)
        ctx.fill(255, 255, 255)
        let g = ctx.canvas.fillColor
        #expect(g.x.isFinite && g.y.isFinite && g.z.isFinite)
    }

    @Test("vertex(x,y,z) inside 2D beginShape routes to the 2D shape")
    func vertex3ArgsInside2DShape() throws {
        let (_, ctx) = try makeContext()
        ctx.beginShape()
        ctx.vertex(0, 0, 0)      // 3 引数だが 2D 記録中 → 2D へ（z 無視）
        ctx.vertex(10, 0, 0)
        ctx.vertex(5, 10, 0)
        #expect(ctx.canvas.shapeVertexList.count == 3,
                "2D 記録中の vertex(x,y,z) は 2D シェイプへルーティングされる")
        ctx.endShape(.close)
        #expect(ctx.activeShapeRecording == .none)
    }

    @Test("vertex(x,y) inside beginShape3D routes to the 3D shape")
    func vertex2ArgsInside3DShape() throws {
        let (_, ctx) = try makeContext()
        ctx.beginShape3D()
        ctx.vertex(0, 0)         // 2 引数だが 3D 記録中 → z=0 で 3D へ
        ctx.vertex(10, 0)
        ctx.vertex(5, 10)
        #expect(ctx.canvas.shapeVertexList.isEmpty,
                "3D 記録中の vertex(x,y) は 2D シェイプに入らない")
        ctx.endShape3D()
        #expect(ctx.activeShapeRecording == .none)
    }

    @Test("millis keeps millisecond resolution after long runtimes")
    func millisDoublePrecision() throws {
        let (_, ctx) = try makeContext()
        ctx.isPrimary = true
        // 100,000 秒（約 27.8 時間）+ 1.5ms。Float 経由では ulp ≈ 7.8ms で丸まる
        ctx.beginFrame(encoder: nil, time: 100000.0015, deltaTime: 0, preciseTime: 100000.0015)
        #expect(millis() == 100000001, "Double 精度で ms 分解能が保たれる (got \(millis()))")
        ctx.beginFrame(encoder: nil, time: 0, deltaTime: 0, preciseTime: 0)  // 復元
    }
}

// MARK: - arc / point の Processing 互換（ピクセル検証）

@Suite("Arc/Point Parity", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ArcPointParityTests {

    /// 1 フレーム描画してピクセルサンプラを返す。
    private func renderAndSample(
        _ body: @escaping (Canvas2D) -> Void
    ) throws -> (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas = try Canvas2D(renderer: renderer)
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, _ in
            canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
            body(canvas)
            canvas.end()
        }
        renderer.renderFrame()

        let w = 64, h = 64
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let staging = try #require(renderer.device.makeTexture(descriptor: desc))
        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        let blit = try #require(cb.makeBlitCommandEncoder())
        blit.copy(from: renderer.textureManager.colorTexture,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return { x, y in
            let off = (y * w + x) * 4
            return (r: px[off + 2], g: px[off + 1], b: px[off + 0])
        }
    }

    @Test("arc .open fill is a chord segment, not a pie")
    func arcOpenFillIsChord() throws {
        let sample = try renderAndSample { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))
            // 1/4 円弧（0 → π/2、y-down で右下方向）
            c.arc(32, 32, 48, 48, 0, .pi / 2, .open)
        }
        // 弓形（弦と弧の間）は塗られる
        let bow = sample(47, 47)
        #expect(bow.r > 200, "弓形の内部は塗られるべき: \(bow)")
        // 中心付近（弦の内側）は塗られない（pie 形状なら塗られていた）
        let nearCenter = sample(35, 35)
        #expect(nearCenter.r < 60, "open モードの fill は中心を含まない弓形であるべき: \(nearCenter)")
    }

    @Test("arc .pie fill includes the center wedge")
    func arcPieFillIncludesCenter() throws {
        let sample = try renderAndSample { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))
            c.arc(32, 32, 48, 48, 0, .pi / 2, .pie)
        }
        let nearCenter = sample(35, 35)
        #expect(nearCenter.r > 200, "pie モードの fill は中心を含む扇形: \(nearCenter)")
    }

    @Test("arc default mode fills a pie shape")
    func arcDefaultFillIsPie() throws {
        let sample = try renderAndSample { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))
            // mode 省略 = Processing のデフォルト（扇形 fill）
            c.arc(32, 32, 48, 48, 0, .pi / 2)
        }
        let nearCenter = sample(35, 35)
        #expect(nearCenter.r > 200, "mode 省略時の fill は中心を含む扇形: \(nearCenter)")
        let bow = sample(47, 47)
        #expect(bow.r > 200, "弓形領域も塗られる: \(bow)")
    }

    @Test("arc default mode strokes only the arc (no chord, no center lines)")
    func arcDefaultStrokeIsOpen() throws {
        let sample = try renderAndSample { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noFill()
            c.stroke(Color(r: 1, g: 0, b: 0))
            c.strokeWeight(3)
            c.arc(32, 32, 48, 48, 0, .pi / 2)
        }
        // 弧上の点（45° 地点 ≈ (32 + 24cos45°, 32 + 24sin45°) ≈ (49, 49)）
        let onArc = sample(49, 49)
        #expect(onArc.r > 200, "弧本体はストロークされる: \(onArc)")
        // 中心→始点の半径線は描かれない（pie なら (44, 32) を通る）
        let onRadius = sample(44, 32)
        #expect(onRadius.r < 60, "mode 省略時の stroke は半径線を描かない: \(onRadius)")
        // 弦は描かれない（chord なら弦 (56,32)-(32,56) の中点 (44, 44) を通る）
        let onChord = sample(44, 44)
        #expect(onChord.r < 60, "mode 省略時の stroke は弦を描かない: \(onChord)")
    }

    @Test("point respects noStroke")
    func pointRespectsNoStroke() throws {
        let sample = try renderAndSample { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.strokeWeight(16)
            c.point(32, 32)
        }
        let p = sample(32, 32)
        #expect(p.r < 30 && p.g < 30 && p.b < 30,
                "noStroke() 中の point() は描画されない: \(p)")
    }
}
