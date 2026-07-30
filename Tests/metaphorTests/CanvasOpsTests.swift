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
}
