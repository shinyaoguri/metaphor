import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Render Regression Tests

@Suite("Render Regression", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct RenderRegressionTests {

    @Test("white clear color fills all pixels")
    func clearWhite() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 1, g: 1, b: 1)
        try helper.render { _ in }

        for (x, y) in [(0, 0), (31, 0), (0, 31), (31, 31), (16, 16)] {
            let p = helper.readPixel(x: x, y: y)
            #expect(p.r > 250, "White clear: pixel (\(x),\(y)) R=\(p.r)")
            #expect(p.g > 250, "White clear: pixel (\(x),\(y)) G=\(p.g)")
            #expect(p.b > 250, "White clear: pixel (\(x),\(y)) B=\(p.b)")
        }
    }

    @Test("black clear color fills all pixels")
    func clearBlack() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { _ in }

        let avg = helper.averageColor(inRect: 0, y: 0, width: 32, height: 32)
        #expect(avg.r < 0.02, "Black clear R=\(avg.r)")
        #expect(avg.g < 0.02, "Black clear G=\(avg.g)")
        #expect(avg.b < 0.02, "Black clear B=\(avg.b)")
    }

    @Test("fill color reflected in drawn rect")
    func fillColorReflected() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.red)
            canvas.noStroke()
            canvas.rect(16, 16, 32, 32)
        }
        // Center of the rect should have reddish pixels
        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.r > 200, "Red fill: R=\(center.r)")
        #expect(center.g < 50, "Red fill: G=\(center.g)")
        #expect(center.b < 50, "Red fill: B=\(center.b)")
    }

    @Test("circle draws non-black pixels in center region")
    func circleDrawsPixels() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.circle(32, 32, 30)
        }
        let hasPixels = helper.hasNonBlackPixels(inRect: 27, y: 27, width: 10, height: 10)
        #expect(hasPixels, "Circle center should have non-black pixels")
    }

    @Test("clear color changes between frames")
    func clearColorChanges() throws {
        var helper = try RenderTestHelper(width: 16, height: 16)

        helper.setClearColor(r: 1, g: 0, b: 0)
        try helper.render { _ in }
        let p1 = helper.readPixel(x: 8, y: 8)

        helper.setClearColor(r: 0, g: 0, b: 1)
        try helper.render { _ in }
        let p2 = helper.readPixel(x: 8, y: 8)

        #expect(p1.r > 200, "First frame should be red: R=\(p1.r)")
        #expect(p1.b < 50, "First frame should be red: B=\(p1.b)")
        #expect(p2.b > 200, "Second frame should be blue: B=\(p2.b)")
        #expect(p2.r < 50, "Second frame should be blue: R=\(p2.r)")
    }

    @Test("rect covers expected region only")
    func rectCoverage() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.rect(0, 0, 32, 32)
        }
        let topLeft = helper.hasNonBlackPixels(inRect: 4, y: 4, width: 8, height: 8)
        #expect(topLeft, "Top-left should have white pixels from rect")

        let bottomRight = helper.hasNonBlackPixels(inRect: 48, y: 48, width: 8, height: 8)
        #expect(!bottomRight, "Bottom-right should remain black")
    }

    /// 単色テクスチャの MImage を作成します（描画順テスト用）。
    private func makeSolidImage(
        device: MTLDevice, width: Int, height: Int,
        b: UInt8, g: UInt8, r: UInt8, a: UInt8 = 255
    ) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = b; pixels[i + 1] = g; pixels[i + 2] = r; pixels[i + 3] = a
        }
        pixels.withUnsafeBytes { buf in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: buf.baseAddress!, bytesPerRow: width * 4)
        }
        return MImage(texture: texture)
    }

    @Test("image drawn after instanced circle renders on top")
    func imageDrawnAfterCircleIsOnTop() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        let white = try #require(makeSolidImage(
            device: helper.device, width: 16, height: 16, b: 255, g: 255, r: 255))
        try helper.render { canvas in
            // インスタンス化される円 → 後から描く画像が上に来なければならない。
            // 画像描画がインスタンスバッチをフラッシュしないと、画像が先に
            // エンコードされて円の下に潜る（リグレッション）。
            canvas.fill(.red)
            canvas.noStroke()
            canvas.circle(32, 32, 40)
            canvas.image(white, 24, 24, 16, 16)
        }
        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.r > 200 && center.g > 200 && center.b > 200,
                "Image should cover the circle: got R=\(center.r) G=\(center.g) B=\(center.b)")
        // 画像の外側はまだ円（赤）のまま
        let ring = helper.readPixel(x: 32, y: 14)
        #expect(ring.r > 200 && ring.g < 50, "Circle should remain outside the image")
    }

    @Test("shape drawn after image renders on top of it")
    func shapeDrawnAfterImageIsOnTop() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        let white = try #require(makeSolidImage(
            device: helper.device, width: 32, height: 32, b: 255, g: 255, r: 255))
        try helper.render { canvas in
            canvas.image(white, 16, 16, 32, 32)
            canvas.fill(.red)
            canvas.noStroke()
            canvas.circle(32, 32, 16)
        }
        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.r > 200 && center.g < 50,
                "Circle should cover the image: got R=\(center.r) G=\(center.g)")
    }

    @Test("beginClip intersects negative-origin rect with the canvas")
    func clipNegativeOrigin() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            // 要求: x:-50..50, y:-50..50 → キャンバスとの交差は 0..50
            canvas.beginClip(-50, -50, 100, 100)
            canvas.rect(0, 0, 64, 64)
            canvas.endClip()
        }
        let inside = helper.readPixel(x: 25, y: 25)
        #expect(inside.r > 200, "Inside the clip should be painted")
        let outside = helper.readPixel(x: 58, y: 58)
        #expect(outside.r < 50, "Outside the 50x50 intersection must stay black")
    }

    @Test("beginClip fully outside the canvas clips everything without crashing")
    func clipFullyOutside() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(.white)
            canvas.noStroke()
            canvas.beginClip(100, 100, 50, 50)
            canvas.rect(0, 0, 64, 64)
            canvas.endClip()
        }
        let avg = helper.averageColor(inRect: 0, y: 0, width: 64, height: 64)
        #expect(avg.r < 0.02, "Nothing should be painted under an off-canvas clip")
    }

    @Test("pop restores blend mode without retroactively changing pending geometry")
    func popFlushesBeforeRestoringBlendMode() throws {
        var helper = try RenderTestHelper(width: 32, height: 32)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.noStroke()
            canvas.push()
            canvas.blendMode(.additive)
            // 加算合成: 0.5 グレーを2回 → ほぼ白
            canvas.fill(Color(r: 0.5, g: 0.5, b: 0.5))
            canvas.rect(0, 0, 32, 32)
            canvas.rect(0, 0, 32, 32)
            canvas.pop()
            // pop 後の図形は通常合成に戻る
        }
        let p = helper.readPixel(x: 16, y: 16)
        #expect(p.r > 220,
                "Two additive 0.5-gray rects should accumulate to ~white (got R=\(p.r)); pop() restoring the blend mode before flushing renders them with .alpha instead")
    }
}
