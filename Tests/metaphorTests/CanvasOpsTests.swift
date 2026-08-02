import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - Canvas 2D Transform Ops (#280)

@Suite("Canvas2D transform ops", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DTransformOpsTests {

    private func makeCanvas() throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: 640,
            height: 360
        )
    }

    @Test("shearX offsets x by tan(angle) * y")
    func shearX() throws {
        let canvas = try makeCanvas()
        let angle = Float.pi / 4  // tan = 1
        canvas.shearX(angle)
        let p = canvas.screenPosition(0, 10)
        #expect(abs(p.x - 10) < 0.001)
        #expect(abs(p.y - 10) < 0.001)
    }

    @Test("shearY offsets y by tan(angle) * x")
    func shearY() throws {
        let canvas = try makeCanvas()
        canvas.shearY(Float.pi / 4)
        let p = canvas.screenPosition(10, 0)
        #expect(abs(p.x - 10) < 0.001)
        #expect(abs(p.y - 10) < 0.001)
    }

    @Test("resetMatrix restores identity")
    func resetMatrix() throws {
        let canvas = try makeCanvas()
        canvas.translate(100, 50)
        canvas.rotate(1.2)
        canvas.resetMatrix()
        let p = canvas.screenPosition(5, 7)
        #expect(abs(p.x - 5) < 0.001)
        #expect(abs(p.y - 7) < 0.001)
    }

    @Test("applyMatrix with Processing-style 6 components")
    func applyMatrixComponents() throws {
        let canvas = try makeCanvas()
        // 行優先: x' = 2x + 0y + 10, y' = 0x + 3y + 20
        canvas.applyMatrix(2, 0, 10, 0, 3, 20)
        let p = canvas.screenPosition(1, 1)
        #expect(abs(p.x - 12) < 0.001)
        #expect(abs(p.y - 23) < 0.001)
    }

    @Test("screenPosition follows translate and rotate")
    func screenPosition() throws {
        let canvas = try makeCanvas()
        canvas.translate(100, 200)
        canvas.rotate(Float.pi / 2)
        // モデル (10, 0) → 回転で (0, 10) → 平行移動で (100, 210)
        let p = canvas.screenPosition(10, 0)
        #expect(abs(p.x - 100) < 0.001)
        #expect(abs(p.y - 210) < 0.001)
    }
}

// MARK: - Canvas 3D Transform Ops (#280)

@Suite("Canvas3D transform ops", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DTransformOpsTests {

    @Test("screenPosition maps world origin to canvas center with default camera")
    func originAtCenter() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)
        let p = canvas3D.screenPosition(0, 0, 0)
        #expect(abs(p.x - canvas3D.width / 2) < 0.5)
        #expect(abs(p.y - canvas3D.height / 2) < 0.5)
        #expect(p.z > 0 && p.z < 1)
    }

    @Test("screenPosition respects model translation and resetMatrix reverts it")
    func modelTransformAndReset() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)
        // +x 方向へ移動すると画面右へ動く
        canvas3D.translate(1, 0, 0)
        let moved = canvas3D.screenPosition(0, 0, 0)
        #expect(moved.x > canvas3D.width / 2)

        canvas3D.resetMatrix()
        let restored = canvas3D.screenPosition(0, 0, 0)
        #expect(abs(restored.x - canvas3D.width / 2) < 0.5)
    }

    // 回帰テスト(#378): screenY(x, y, z) が 2D の screenY(x, y) と同じ座標系
    // (左上原点・下方向が +Y)を返すことを固定する。中心点だけでは符号の
    // 誤りが打ち消し合って検出できないため、中心から外れた y で検証する。
    @Test("screenPosition maps off-center y consistently with 2D screen space (regression #378)")
    func offCenterYMatchesScreenSpaceConvention() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)
        // begin() は Processing 風の既定カメラ(cameraEye = (w/2, h/2, defaultZ),
        // center = (w/2, h/2, 0))をフレームごとに設定する。実際のスケッチはこの
        // カメラで screenX/screenY を評価するため、それを再現する
        // (Canvas3D 単体初期化直後は無関係な eye = (0,0,5) のまま)。
        canvas3D.begin(encoder: nil, time: 0)
        let centerX = canvas3D.width / 2
        let centerY = canvas3D.height / 2

        // 既定カメラは z=0 平面でワールド 1 単位 = 画面 1px に較正されているため、
        // 中心より 100 だけ上のワールド y は screenY でも中心より 100 だけ上(小さい値)になるはず。
        let above = canvas3D.screenPosition(centerX, centerY - 100, 0)
        #expect(abs(above.y - (centerY - 100)) < 1.0)

        // 中心より 100 だけ下も同様に screenY が中心より大きい値になるはず。
        let below = canvas3D.screenPosition(centerX, centerY + 100, 0)
        #expect(abs(below.y - (centerY + 100)) < 1.0)
    }
}

// MARK: - MImage resize / mask (#280)

@Suite("MImage resize and mask", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MImageResizeMaskTests {

    private func makeImage(_ w: Int, _ h: Int, fill: Color) -> MImage? {
        let device = MTLCreateSystemDefaultDevice()!
        guard let img = MImage.createImage(w, h, device: device) else { return nil }
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                img.set(x, y, fill)
            }
        }
        img.updatePixels()
        return img
    }

    @Test("resize scales to explicit dimensions and keeps solid color")
    func resizeExplicit() throws {
        let img = try #require(makeImage(64, 32, fill: Color(r: 1, g: 0, b: 0)))
        img.resize(32, 16)
        #expect(Int(img.width) == 32)
        #expect(Int(img.height) == 16)
        // 単色画像はバイリニア縮小後も単色
        img.loadPixels()
        let c = img.get(8, 8)
        #expect(c.r > 0.95)
        #expect(c.g < 0.05)
    }

    @Test("resize with zero keeps aspect ratio")
    func resizeAspect() throws {
        let img = try #require(makeImage(64, 32, fill: Color(r: 0, g: 1, b: 0)))
        img.resize(32, 0)
        #expect(Int(img.width) == 32)
        #expect(Int(img.height) == 16)

        img.resize(0, 8)
        #expect(Int(img.width) == 16)
        #expect(Int(img.height) == 8)
    }

    @Test("resize with both dimensions zero is a no-op")
    func resizeZeroNoOp() throws {
        let img = try #require(makeImage(64, 32, fill: Color(r: 1, g: 1, b: 1)))
        img.resize(0, 0)
        #expect(Int(img.width) == 64)
        #expect(Int(img.height) == 32)
    }

    @Test("mask sets alpha from mask blue channel")
    func maskAppliesBlueChannel() throws {
        let img = try #require(makeImage(8, 8, fill: Color(r: 1, g: 0, b: 0, a: 1)))
        // マスク: 青 0.5 → アルファ約 0.5 になる
        let maskImg = try #require(makeImage(8, 8, fill: Color(r: 0, g: 0, b: 0.5)))
        img.mask(maskImg)
        img.loadPixels()
        let a = img.get(4, 4).a
        #expect(abs(a - 0.5) < 0.02)
    }

    @Test("mask with mismatched size is a no-op")
    func maskSizeMismatch() throws {
        let img = try #require(makeImage(8, 8, fill: Color(r: 1, g: 0, b: 0, a: 1)))
        let maskImg = try #require(makeImage(4, 4, fill: Color(r: 0, g: 0, b: 0)))
        img.mask(maskImg)
        img.loadPixels()
        #expect(img.get(4, 4).a > 0.99)
    }
}

// MARK: - keyTyped character detection (#280)

@Suite("keyTyped character detection")
struct KeyTypedDetectionTests {

    @Test("printable characters produce keyTyped")
    func printable() {
        #expect(SketchRunner.producesCharacter("a"))
        #expect(SketchRunner.producesCharacter("A"))
        #expect(SketchRunner.producesCharacter("1"))
        #expect(SketchRunner.producesCharacter("あ"))
        // Enter/Tab/Delete も Processing では keyTyped が発火する
        #expect(SketchRunner.producesCharacter("\r"))
        #expect(SketchRunner.producesCharacter("\t"))
    }

    @Test("function keys (Unicode PUA) and empty input do not produce keyTyped")
    func functionKeys() {
        #expect(!SketchRunner.producesCharacter("\u{F700}"))  // 上矢印
        #expect(!SketchRunner.producesCharacter("\u{F704}"))  // F1
        #expect(!SketchRunner.producesCharacter("\u{F8FF}"))  // PUA 上端
        #expect(!SketchRunner.producesCharacter(nil))
        #expect(!SketchRunner.producesCharacter(""))
    }
}

// MARK: - SketchContext copy (#280)

@Suite("SketchContext copy", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CanvasCopyTests {

    private func makeContext() throws -> (Canvas2D, SketchContext) {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        return (canvas, context)
    }

    @Test("copy with invalid sizes or out-of-canvas region is a no-op")
    func copyValidation() throws {
        let (_, context) = try makeContext()
        // 負サイズ・ゼロサイズ・完全に範囲外 — いずれもクラッシュせず no-op
        context.copy(0, 0, -10, 10, 0, 0, 10, 10)
        context.copy(0, 0, 0, 0, 0, 0, 10, 10)
        context.copy(10000, 10000, 50, 50, 0, 0, 50, 50)
    }

    @Test("copy restores imageMode and tint after drawing")
    func copyRestoresState() throws {
        let (canvas, context) = try makeContext()
        canvas.imageMode(.center)
        canvas.hasTint = true
        context.copy(0, 0, 100, 100, 200, 200, 50, 50)
        #expect(canvas.currentImageMode == .center)
        #expect(canvas.hasTint == true)
    }

    /// #308 再現: copy() はキャンバスの内容を写す(未初期化テクスチャではなく)
    @Test("copy draws the previous frame's canvas content, not uninitialized memory")
    func copyDrawsCanvasContent() throws {
        var frameIndex = 0
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            if frameIndex == 0 {
                // フレーム 1: 左上 32x32 に赤い矩形
                context.background(Color(r: 0, g: 0, b: 0))
                context.fill(Color(r: 1, g: 0, b: 0))
                context.noStroke()
                context.rect(0, 0, 32, 32)
            } else {
                // フレーム 2: 前フレームの左上を右下 32x32 へコピー
                context.background(Color(r: 0, g: 0, b: 0))
                context.copy(0, 0, 32, 32, 32, 32, 32, 32)
            }
            frameIndex += 1
            context.endFrame()
        }
        renderer.renderFrame()  // フレーム 1: 赤い矩形
        renderer.renderFrame()  // フレーム 2: copy

        context.loadPixels()
        let pb = try #require(context.pixelBuffer)
        // コピー先の中心 (48, 48): フレーム 1 の赤が写っているべき
        let dst = pb.pixels[48 * 64 + 48]
        let dstR = (dst >> 16) & 0xFF
        let dstG = (dst >> 8) & 0xFF
        let dstB = dst & 0xFF
        #expect(dstR > 200, "copy destination should be red (R=\(dstR), pixel=\(String(dst, radix: 16)))")
        #expect(dstG < 50 && dstB < 50,
                "copy destination should be pure red, not garbage (G=\(dstG), B=\(dstB))")
        // コピーされていない左下 (8, 48) は黒のまま
        let untouched = pb.pixels[48 * 64 + 8]
        #expect((untouched >> 16) & 0xFF < 50, "area outside copy destination stays black")
    }

    /// #308 再現: フレーム 1 の copy() はクリア済みキャンバス(クリア色)を写す。
    /// 前フレームが存在しない初回でも、未初期化 VRAM の内容を描いてはならない。
    @Test("copy on the very first frame reads the cleared canvas, not uninitialized memory")
    func copyFirstFrameReadsClearedCanvas() throws {
        // クリア色を赤に: 初回 copy が「クリア済みテクスチャ」を読めばコピー先も赤になる
        // (未初期化 VRAM なら赤にはならないため決定的に検証できる)
        let renderer = try MetaphorRenderer(
            width: 64, height: 64,
            clearColor: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            context.copy(0, 0, 32, 32, 32, 32, 32, 32)
            context.endFrame()
        }
        renderer.renderFrame()  // 最初のフレームで即 copy

        context.loadPixels()
        let pb = try #require(context.pixelBuffer)
        let dst = pb.pixels[48 * 64 + 48]
        let dstR = (dst >> 16) & 0xFF
        let dstG = (dst >> 8) & 0xFF
        let dstB = dst & 0xFF
        #expect(dstR > 200 && dstG < 50 && dstB < 50,
                "first-frame copy should show the clear color (red), got \(String(dst, radix: 16))")
    }
}
