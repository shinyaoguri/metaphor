import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Graphics3D Creation

@Suite("Graphics3D Creation", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Graphics3DCreationTests {

    @Test("creation succeeds")
    func creation() throws {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 400,
            height: 300
        )
        #expect(pg3d.width == 400)
        #expect(pg3d.height == 300)
    }

    @Test("custom dimensions")
    func dimensions() throws {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 800,
            height: 600
        )
        #expect(pg3d.width == 800)
        #expect(pg3d.height == 600)
    }

    @Test("texture exists with correct size")
    func textureExists() throws {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 400,
            height: 300
        )
        #expect(pg3d.texture.width == 400)
        #expect(pg3d.texture.height == 300)
    }

    @Test("Graphics first background fills target")
    func graphicsFirstBackgroundFillsTarget() throws {
        let renderer = try MetaphorRenderer(width: 8, height: 8)
        let pg = try Graphics(
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: 8,
            height: 8
        )

        pg.beginDraw()
        pg.background(Color(r: 1, g: 0, b: 0))
        // CPU 側で直接ピクセルを読むので明示的に GPU 完了を待つ
        pg.endDraw(wait: true)

        let image = pg.toImage()
        image.loadPixels()
        let color = image.get(4, 4)
        #expect(color.r > 0.9)
        #expect(color.g < 0.1)
        #expect(color.b < 0.1)
    }
}

// MARK: - Graphics3D Lifecycle

@Suite("Graphics3D Lifecycle", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Graphics3DLifecycleTests {

    private func makeGraphics3D(width: Int = 400, height: Int = 300) throws -> Graphics3D {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        return try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height
        )
    }

    @Test("beginDraw and endDraw cycle produces valid texture")
    func beginEndDraw() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.endDraw()
        #expect(pg3d.texture.width == 400)
        #expect(pg3d.texture.height == 300)
    }

    @Test("toImage returns correct dimensions")
    func toImage() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.endDraw()
        let img = pg3d.toImage()
        #expect(img.width == 400)
        #expect(img.height == 300)
    }

    @Test("draw primitives produces valid output")
    func drawPrimitives() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.lights()
        pg3d.fill(.red)
        pg3d.box(100)
        pg3d.endDraw()
        let img = pg3d.toImage()
        #expect(img.width == 400)
        #expect(img.height == 300)
    }

    @Test("multiple draw cycles produce valid output each time")
    func multipleDrawCycles() throws {
        let pg3d = try makeGraphics3D()
        for i in 0..<3 {
            pg3d.beginDraw()
            pg3d.fill(.blue)
            pg3d.sphere(50)
            pg3d.endDraw()
            let img = pg3d.toImage()
            #expect(img.width == 400, "cycle \(i): width mismatch")
        }
    }
}

// MARK: - Graphics3D Transforms & Lighting

@Suite("Graphics3D Transforms", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Graphics3DTransformTests {

    private func makeGraphics3D() throws -> Graphics3D {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        return try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 400,
            height: 300
        )
    }

    @Test("transform methods produce valid output")
    func transformMethods() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.pushMatrix()
        pg3d.translate(1, 2, 3)
        pg3d.rotateX(0.5)
        pg3d.rotateY(0.5)
        pg3d.rotateZ(0.5)
        pg3d.scale(2, 2, 2)
        pg3d.box(50)
        pg3d.popMatrix()
        pg3d.endDraw()
        let img = pg3d.toImage()
        #expect(img.width == 400)
        #expect(img.height == 300)
    }

    @Test("camera and lighting produce valid output")
    func cameraAndLighting() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.camera(
            eye: SIMD3(0, 0, 5),
            center: SIMD3(0, 0, 0)
        )
        pg3d.lights()
        pg3d.directionalLight(0, -1, 0)
        pg3d.pointLight(0, 3, 0)
        // ambientLight は colorMode 基準（既定 0〜255）。77 ≒ 既定アンビエント（レンジの 30%）。
        pg3d.ambientLight(77)
        pg3d.fill(.white)
        pg3d.box(100)
        pg3d.endDraw()
        let img = pg3d.toImage()
        #expect(img.width == 400)
        #expect(img.height == 300)
    }

    @Test("box with lights produces non-black pixels at center")
    func boxWithLightsPixelCheck() throws {
        // Center box in the Processing-like coordinate system
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.lights()
        pg3d.fill(Color(r: 1, g: 1, b: 1, alpha: 1))
        pg3d.translate(200, 150, 0)  // center of 400x300
        pg3d.box(100)
        pg3d.endDraw()

        let img = pg3d.toImage()
        img.loadPixels()

        // Scan entire image for any non-black pixel
        var maxR: Float = 0
        var maxG: Float = 0
        var maxB: Float = 0
        var nonBlackCount = 0
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let c = img.get(x, y)
                maxR = max(maxR, c.r)
                maxG = max(maxG, c.g)
                maxB = max(maxB, c.b)
                if c.r > 0.01 || c.g > 0.01 || c.b > 0.01 {
                    nonBlackCount += 1
                }
            }
        }
        #expect(nonBlackCount > 0, "Box with lights: nonBlack=\(nonBlackCount), maxRGB=(\(maxR),\(maxG),\(maxB))")
    }

    @Test("box without lights produces non-black pixels (unlit)")
    func boxWithoutLightsPixelCheck() throws {
        // Test unlit path: lightCount == 0, should return vertex color directly
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.fill(Color(r: 1, g: 1, b: 1, alpha: 1))
        pg3d.translate(200, 150, 0)
        pg3d.box(100)
        pg3d.endDraw()

        let img = pg3d.toImage()
        img.loadPixels()

        var maxR: Float = 0
        var maxG: Float = 0
        var maxB: Float = 0
        var nonBlackCount = 0
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let c = img.get(x, y)
                maxR = max(maxR, c.r)
                maxG = max(maxG, c.g)
                maxB = max(maxB, c.b)
                if c.r > 0.01 || c.g > 0.01 || c.b > 0.01 {
                    nonBlackCount += 1
                }
            }
        }
        #expect(nonBlackCount > 0, "Box unlit: nonBlack=\(nonBlackCount), maxRGB=(\(maxR),\(maxG),\(maxB))")
    }

    @Test("Primitives3D exact reproduction - box at (130, 180, 0)")
    func primitives3DExactReproduction() throws {
        // Exact reproduction of the Primitives3D example
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 640,
            height: 360
        )
        pg3d.beginDraw()
        pg3d.lights()

        // Box (filled, no stroke)
        pg3d.pushMatrix()
        pg3d.translate(130, 180, 0)  // height/2 = 180
        pg3d.rotateY(1.25)
        pg3d.rotateX(-0.4)
        pg3d.box(100)
        pg3d.popMatrix()

        pg3d.endDraw()

        let img = pg3d.toImage()
        img.loadPixels()

        // Scan left half of image for the box
        var nonBlackCount = 0
        var maxR: Float = 0
        for y in 0..<Int(img.height) {
            for x in 0..<(Int(img.width) / 2) {
                let c = img.get(x, y)
                maxR = max(maxR, c.r)
                if c.r > 0.01 || c.g > 0.01 || c.b > 0.01 {
                    nonBlackCount += 1
                }
            }
        }
        #expect(nonBlackCount > 100, "Primitives3D box: nonBlack=\(nonBlackCount), maxR=\(maxR)")
    }

    @Test("Canvas2D background + Canvas3D box (mimics SketchRunner)")
    func canvas2DPlusCanvas3DBox() throws {
        // This test reproduces the actual SketchRunner flow with Canvas2D + Canvas3D
        let renderer = try MetaphorRenderer()
        let canvas2D = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }

        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        // beginFrame: both canvases begin
        canvas3D.begin(encoder: encoder, time: 0)
        canvas2D.begin(encoder: encoder)

        // background(0) via Canvas2D
        canvas2D.background(0)

        // lights + box via Canvas3D
        canvas3D.lights()
        canvas3D.translate(Float(renderer.textureManager.width) / 2,
                          Float(renderer.textureManager.height) / 2, 0)
        canvas3D.box(100)

        // endFrame: flush both
        canvas3D.end()
        canvas2D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back pixels from colorTexture
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height
        let tex = renderer.textureManager.colorTexture

        // Create staging texture for readback
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc) else {
            Issue.record("Failed to create staging texture")
            return
        }

        guard let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else {
            Issue.record("Failed to create blit encoder")
            return
        }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&pixels, bytesPerRow: w * 4,
                        from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        var nonBlackCount = 0
        var maxVal: UInt8 = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            let g = pixels[i + 1]
            let r = pixels[i + 2]
            maxVal = max(maxVal, r, g, b)
            if r > 2 || g > 2 || b > 2 {
                nonBlackCount += 1
            }
        }
        #expect(nonBlackCount > 100,
                "Canvas2D+Canvas3D: nonBlack=\(nonBlackCount), maxVal=\(maxVal), sampleCount=\(renderer.textureManager.sampleCount)")
    }

    @Test("noLoop two-frame rendering reproduces Primitives3D")
    func noLoopTwoFrameRendering() throws {
        // Reproduce the exact noLoop() two-frame system from SketchRunner
        let renderer = try MetaphorRenderer()
        let canvas2D = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)

        canvas2D.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)

        // Helper to simulate one frame's draw()
        func drawFrame() {
            canvas2D.background(0)
            canvas3D.lights()
            canvas3D.pushState()
            canvas3D.translate(w / 2, h / 2, 0)
            canvas3D.rotateY(1.25)
            canvas3D.rotateX(-0.4)
            canvas3D.box(100)
            canvas3D.popState()
        }

        // --- Frame 1: off-screen only (like renderer.renderFrame()) ---
        // frameBufferIndex is read-only; just use default (0)
        if let cb1 = renderer.commandQueue.makeCommandBuffer() {
            let rpd1 = renderer.textureManager.renderPassDescriptor
            if let enc1 = cb1.makeRenderCommandEncoder(descriptor: rpd1) {
                canvas3D.begin(encoder: enc1, time: 0, bufferIndex: 0)
                canvas2D.begin(encoder: enc1, bufferIndex: 0)
                drawFrame()
                canvas3D.end()
                canvas2D.end()
                enc1.endEncoding()
            }
            // endFrame bookkeeping
            let shouldClear = canvas2D.backgroundCalledThisFrame
            renderer.textureManager.setShouldClear(shouldClear)
            canvas2D.frameWillClear = shouldClear
            if shouldClear { canvas2D.markPendingClearColorApplied() }

            cb1.commit()
            cb1.waitUntilCompleted()
        }

        // --- Frame 2: actual render (like mtkView.draw() → renderFrame()) ---
        // Frame 2 uses different buffer index
        if let cb2 = renderer.commandQueue.makeCommandBuffer() {
            let rpd2 = renderer.textureManager.renderPassDescriptor
            if let enc2 = cb2.makeRenderCommandEncoder(descriptor: rpd2) {
                canvas3D.begin(encoder: enc2, time: 0.016, bufferIndex: 1)
                canvas2D.begin(encoder: enc2, bufferIndex: 1)
                drawFrame()
                canvas3D.end()
                canvas2D.end()
                enc2.endEncoding()
            }
            let shouldClear2 = canvas2D.backgroundCalledThisFrame
            renderer.textureManager.setShouldClear(shouldClear2)
            canvas2D.frameWillClear = shouldClear2
            if shouldClear2 { canvas2D.markPendingClearColorApplied() }

            cb2.commit()
            cb2.waitUntilCompleted()
        }

        // Read back pixels from Frame 2
        let width = renderer.textureManager.width
        let height = renderer.textureManager.height
        let tex = renderer.textureManager.colorTexture

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc) else {
            Issue.record("staging failed")
            return
        }
        guard let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else {
            Issue.record("blit failed")
            return
        }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        staging.getBytes(&pixels, bytesPerRow: width * 4,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        var nonBlackCount = 0
        var maxVal: UInt8 = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[i + 2]
            let g = pixels[i + 1]
            let b = pixels[i]
            maxVal = max(maxVal, r, g, b)
            if r > 2 || g > 2 || b > 2 { nonBlackCount += 1 }
        }
        #expect(nonBlackCount > 100,
                "noLoop 2-frame: nonBlack=\(nonBlackCount), maxVal=\(maxVal)")
    }
}

// MARK: - Canvas3D Batch Flush Regression

@Suite("Canvas3D Batch Flush Regression", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DBatchFlushTests {

    /// renderer.textureManager.colorTexture を読み戻して非黒ピクセル数を返します。
    private func countNonBlackPixels(renderer: MetaphorRenderer) -> Int {
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc),
              let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else { return -1 }
        blit.copy(from: renderer.textureManager.colorTexture,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&pixels, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var nonBlack = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[i] > 2 || pixels[i + 1] > 2 || pixels[i + 2] > 2 { nonBlack += 1 }
        }
        return nonBlack
    }

    @Test("camera() change does not retroactively apply to already-submitted shapes")
    func cameraChangeDoesNotAffectSubmittedShapes() throws {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        let pg3d = try Graphics3D(
            device: device,
            commandQueue: MetalTestHelper.commandQueue()!,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 400, height: 300
        )
        pg3d.beginDraw()
        pg3d.lights()
        pg3d.fill(.red)
        pg3d.translate(200, 150, 0)
        pg3d.box(120)
        // 送信済みの box は送信時点のカメラで描画されなければならない。
        // カメラ変更がペンディングのインスタンスバッチをフラッシュしない場合、
        // box はこの「シーン外を向いた」カメラで描かれて消える。
        pg3d.camera(eye: SIMD3(0, 0, -10000), center: SIMD3(0, 0, -20000))
        pg3d.endDraw(wait: true)

        let img = pg3d.toImage()
        img.loadPixels()
        var nonBlack = 0
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let c = img.get(x, y)
                if c.r > 0.01 || c.g > 0.01 || c.b > 0.01 { nonBlack += 1 }
            }
        }
        #expect(nonBlack > 100,
                "Box must be rendered with the camera that was active when it was submitted (nonBlack=\(nonBlack))")
    }

    @Test("beginShape polygon with more than 85 vertices renders (exceeds setVertexBytes 4KB limit)")
    func largeBeginShapePolygon() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        canvas3D.begin(encoder: encoder, time: 0)
        canvas3D.fill(.white)
        canvas3D.noStroke()
        canvas3D.translate(Float(renderer.textureManager.width) / 2,
                           Float(renderer.textureManager.height) / 2, 0)
        // 120 頂点の多角形 → 三角形化で 354 頂点 ≒ 17KB（4KB 制限を大きく超える）
        canvas3D.beginShape()
        let n = 120
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * Float.pi
            canvas3D.vertex(cos(a) * 150, sin(a) * 150, 0)
        }
        canvas3D.endShape(.close)
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let nonBlack = countNonBlackPixels(renderer: renderer)
        #expect(nonBlack > 1000,
                "120-vertex polygon should render via the transient-buffer path (nonBlack=\(nonBlack))")
    }

    @Test("multiple large beginShape polygons in one frame render independently (#250 bump-allocated ring)")
    func multipleLargeBeginShapePolygons() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)
        let radius = min(w, h) * 0.2

        canvas3D.begin(encoder: encoder, time: 0)
        canvas3D.fill(.white)
        canvas3D.noStroke()
        // 左右に 1 個ずつ、4KB 制限を超える 120 頂点ポリゴンを同一フレームで描く。
        // 2 個目のシェイプのバンプ確保（永続リングの offset 進行）が 1 個目の
        // 頂点データを上書き・破壊しないことの回帰テスト
        for cx in [w * 0.25, w * 0.75] {
            canvas3D.pushMatrix()
            canvas3D.translate(cx, h / 2, 0)
            canvas3D.beginShape()
            let n = 120
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * Float.pi
                canvas3D.vertex(cos(a) * radius, sin(a) * radius, 0)
            }
            canvas3D.endShape(.close)
            canvas3D.popMatrix()
        }
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // 左半分・右半分それぞれに描かれていることを個別に確認する
        // （全域カウントでは片方が消えても他方で合格し得るため）
        let texW = renderer.textureManager.width
        let texH = renderer.textureManager.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: texW, height: texH, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc),
              let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else {
            Issue.record("Failed to create readback resources")
            return
        }
        blit.copy(from: renderer.textureManager.colorTexture,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texW, height: texH, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: texW * texH * 4)
        staging.getBytes(&pixels, bytesPerRow: texW * 4,
                         from: MTLRegionMake2D(0, 0, texW, texH), mipmapLevel: 0)
        var nonBlackLeft = 0
        var nonBlackRight = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4
                if pixels[i] > 2 || pixels[i + 1] > 2 || pixels[i + 2] > 2 {
                    if x < texW / 2 { nonBlackLeft += 1 } else { nonBlackRight += 1 }
                }
            }
        }
        #expect(nonBlackLeft > 500,
                "First large polygon (left) must survive the second bump allocation (nonBlackLeft=\(nonBlackLeft))")
        #expect(nonBlackRight > 500,
                "Second large polygon (right) must render at its own ring offset (nonBlackRight=\(nonBlackRight))")
    }
}

// MARK: - beginShape の stroke（#429）

@Suite("Canvas3D Shape Stroke", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DShapeStrokeTests {

    /// colorTexture を BGRA8 で読み戻します。
    private func readback(renderer: MetaphorRenderer) -> (pixels: [UInt8], width: Int, height: Int)? {
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc),
              let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: renderer.textureManager.colorTexture,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&pixels, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return (pixels, w, h)
    }

    /// 半径 radius の正三角形を beginShape/endShape で 1 枚描きます。
    private func triangle(_ canvas3D: Canvas3D, radius: Float) {
        canvas3D.beginShape()
        for i in 0..<3 {
            let a = Float(i) / 3 * 2 * Float.pi - Float.pi / 2
            canvas3D.vertex(cos(a) * radius, sin(a) * radius, 0)
        }
        canvas3D.endShape(.close)
    }

    @Test("stroke-only shape survives when a filled shape is drawn in the same frame (#429)")
    func strokeOnlyShapeCoexistsWithFilledShape() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)
        let radius = min(w, h) * 0.2

        canvas3D.begin(encoder: encoder, time: 0)
        // 右: fill のみ（青）。この fill 色が以降の vertex() に焼き込まれる
        canvas3D.pushMatrix()
        canvas3D.translate(w * 0.75, h / 2, 0)
        canvas3D.noStroke()
        canvas3D.fill(0, 0, 255)
        triangle(canvas3D, radius: radius)
        canvas3D.popMatrix()
        // 左: stroke のみ（赤のワイヤーフレーム）。noFill でも直前の fill 色は
        // 頂点カラーとして残るため、線が「青 × 赤 = 黒」になって丸ごと消えていた
        // のが #429 の症状 B。stroke 色だけで描かれなければならない
        canvas3D.pushMatrix()
        canvas3D.translate(w * 0.25, h / 2, 0)
        canvas3D.noFill()
        canvas3D.stroke(255, 0, 0)
        triangle(canvas3D, radius: radius)
        canvas3D.popMatrix()
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let (pixels, texW, texH) = readback(renderer: renderer) else {
            Issue.record("Failed to read back color texture")
            return
        }
        var redLeft = 0
        var blueRight = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                let b = pixels[i], r = pixels[i + 2]
                if x < texW / 2 {
                    if r > 128 && b < 64 { redLeft += 1 }
                } else {
                    if b > 128 && r < 64 { blueRight += 1 }
                }
            }
        }
        #expect(redLeft > 100,
                "Stroke-only shape must keep its own stroke color next to a filled one (redLeft=\(redLeft))")
        #expect(blueRight > 100,
                "Filled shape must render (blueRight=\(blueRight))")
    }

    @Test("stroke is visible on a shape that also has fill (#429)")
    func strokeVisibleOnFilledShape() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)

        canvas3D.begin(encoder: encoder, time: 0)
        canvas3D.translate(w / 2, h / 2, 0)
        // fill は青、stroke は赤。同一ジオメトリを 2 パスで描くため、深度比較が
        // 厳密な `<` だと後から来る線が等深度で不合格になり赤が 1 画素も出ない
        canvas3D.fill(0, 0, 255)
        canvas3D.stroke(255, 0, 0)
        triangle(canvas3D, radius: min(w, h) * 0.4)
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let (pixels, texW, texH) = readback(renderer: renderer) else {
            Issue.record("Failed to read back color texture")
            return
        }
        var redPixels = 0
        var bluePixels = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                let b = pixels[i], r = pixels[i + 2]
                if r > 128 && b < 64 { redPixels += 1 }
                if b > 128 && r < 64 { bluePixels += 1 }
            }
        }
        #expect(bluePixels > 100, "Fill must render (bluePixels=\(bluePixels))")
        #expect(redPixels > 50,
                "Stroke must be visible over the fill of the same shape (redPixels=\(redPixels))")
    }

    @Test("stroke on a primitive mesh uses the stroke color, not the fill color (#429)")
    func strokeColorOnPrimitiveMesh() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)

        canvas3D.begin(encoder: encoder, time: 0)
        canvas3D.translate(w / 2, h / 2, 0)
        // インスタンス経路（box / sphere など）のワイヤーはインスタンス色
        // （= fill 色）で描かれていたため、stroke 色が反映されなかった
        canvas3D.fill(0, 0, 255)
        canvas3D.stroke(255, 0, 0)
        canvas3D.box(min(w, h) * 0.5)
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let (pixels, texW, texH) = readback(renderer: renderer) else {
            Issue.record("Failed to read back color texture")
            return
        }
        var redPixels = 0
        var bluePixels = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                let b = pixels[i], r = pixels[i + 2]
                if r > 128 && b < 64 { redPixels += 1 }
                if b > 128 && r < 64 { bluePixels += 1 }
            }
        }
        #expect(bluePixels > 100, "Box fill must render (bluePixels=\(bluePixels))")
        #expect(redPixels > 50,
                "Box wireframe must be drawn in the stroke color (redPixels=\(redPixels))")
    }
}

// MARK: - UV テストの共通ハーネス（#433 / #435）

/// UV 付き描画のピクセル検証で使う共通処理。`beginShape3D`（#433）と
/// `DynamicMesh`（#435）のどちらのテストからも使う。
@MainActor
fileprivate enum UVTestSupport {

    /// colorTexture を BGRA8 で読み戻します。
    static func readback(renderer: MetaphorRenderer) -> (pixels: [UInt8], width: Int, height: Int)? {
        let w = renderer.textureManager.width
        let h = renderer.textureManager.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        guard let staging = renderer.device.makeTexture(descriptor: desc),
              let blitCB = renderer.commandQueue.makeCommandBuffer(),
              let blit = blitCB.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: renderer.textureManager.colorTexture,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        blitCB.commit()
        blitCB.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        staging.getBytes(&pixels, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return (pixels, w, h)
    }

    /// 左半分が赤・右半分が緑の 2×1 テクスチャ（BGRA8）。
    static func makeHalfRedHalfGreenTexture(device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 2, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        // BGRA 並び: 左 = 赤(0,0,255,255)、右 = 緑(0,255,0,255)
        let bytes: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0,
                    withBytes: bytes, bytesPerRow: 2 * 4)
        return MImage(texture: tex)
    }

    /// 赤画素・緑画素の個数と平均 x を数えます。
    static func scanRedGreen(_ pixels: [UInt8], _ texW: Int, _ texH: Int)
        -> (red: Int, green: Int, redMeanX: Float, greenMeanX: Float) {
        var red = 0, green = 0
        var redSumX = 0, greenSumX = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                let b = pixels[i], g = pixels[i + 1], r = pixels[i + 2]
                if r > 128 && g < 96 && b < 96 { red += 1; redSumX += x }
                if g > 128 && r < 96 && b < 96 { green += 1; greenSumX += x }
            }
        }
        return (red, green,
                red > 0 ? Float(redSumX) / Float(red) : 0,
                green > 0 ? Float(greenSumX) / Float(green) : 0)
    }

    /// 1 フレーム描画して読み戻す共通ハーネス。
    static func render(_ body: (Canvas3D, Float, Float) -> Void) throws
        -> (pixels: [UInt8], width: Int, height: Int)? {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return nil
        }
        let rpd = renderer.textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            Issue.record("Failed to create encoder")
            return nil
        }

        let w = Float(renderer.textureManager.width)
        let h = Float(renderer.textureManager.height)

        canvas3D.begin(encoder: encoder, time: 0)
        body(canvas3D, w, h)
        canvas3D.end()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return readback(renderer: renderer)
    }
}

// MARK: - Canvas3D Shape UV (#433)

@Suite("Canvas3D Shape UV", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DShapeUVTests {

    /// `bindShapeVertices` は `Vertex3D` 用のリング（`GrowableGPUBuffer<Vertex3D>`）を
    /// `Vertex3DTextured` と共有する。両者の stride が一致することが前提。
    @Test("Vertex3D and Vertex3DTextured share the same stride")
    func vertexStridesMatch() {
        #expect(MemoryLayout<Vertex3DTextured>.stride == MemoryLayout<Vertex3D>.stride)
    }

    /// 画面中央に一辺 `size` の quad を UV つきで描きます（左端 u=0 / 右端 u=1）。
    private func texturedQuad(_ canvas3D: Canvas3D, w: Float, h: Float, size: Float,
                              mode: ShapeMode = .polygon) {
        let cx = w / 2, cy = h / 2, s = size / 2
        canvas3D.beginShape(mode)
        switch mode {
        case .triangleStrip:
            // strip の頂点順（左上 → 左下 → 右上 → 右下）
            canvas3D.vertex(cx - s, cy - s, 0, 0, 0)
            canvas3D.vertex(cx - s, cy + s, 0, 0, 1)
            canvas3D.vertex(cx + s, cy - s, 0, 1, 0)
            canvas3D.vertex(cx + s, cy + s, 0, 1, 1)
        default:
            canvas3D.vertex(cx - s, cy - s, 0, 0, 0)
            canvas3D.vertex(cx + s, cy - s, 0, 1, 0)
            canvas3D.vertex(cx + s, cy + s, 0, 1, 1)
            canvas3D.vertex(cx - s, cy + s, 0, 0, 1)
        }
        canvas3D.endShape(.close)
    }

    @Test("vertex(x,y,z,u,v) maps the texture across a beginShape3D quad")
    func texturedQuadSamplesTexture() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            // fill は白。テクスチャ色は fill 色で tint されるため、UV が効かなければ全面白になる
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            texturedQuad(canvas3D, w: w, h: h, size: min(w, h) * 0.6)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "Left half must sample the red texel (red=\(scan.red))")
        #expect(scan.green > 100, "Right half must sample the green texel (green=\(scan.green))")
        #expect(scan.redMeanX < scan.greenMeanX,
                "u=0 must land left of u=1 (redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX))")
    }

    @Test("UV is ignored when no texture is bound")
    func uvWithoutTextureFallsBackToFill() throws {
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 0, 0)  // 赤の fill だけで塗られること
            texturedQuad(canvas3D, w: w, h: h, size: min(w, h) * 0.6)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "Shape must still be filled (red=\(scan.red))")
        #expect(scan.green == 0, "No texture is bound, so no texel color may appear (green=\(scan.green))")
    }

    @Test("texture() without UV vertices keeps the plain fill path")
    func textureWithoutUVKeepsFillPath() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // texture() を呼んでも vertex(x,y,z) だけで組んだシェイプは従来どおり fill で塗る
        // （テクスチャ座標がないため。UV 対応の前後で挙動が変わらないことを固定する）
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            // fill は白。UV 経路へ誤って入ると全頂点 uv=(0,0) でテクスチャ左端の
            // 赤をサンプルするため、赤画素の有無で取り違えを検出できる
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            let cx = w / 2, cy = h / 2, s = min(w, h) * 0.3
            canvas3D.beginShape()
            canvas3D.vertex(cx - s, cy - s, 0)
            canvas3D.vertex(cx + s, cy - s, 0)
            canvas3D.vertex(cx + s, cy + s, 0)
            canvas3D.vertex(cx - s, cy + s, 0)
            canvas3D.endShape(.close)
        }) else { return }

        // 正しい挙動では quad は fill 色の白のまま。テクスチャ経路へ入ると
        // 全頂点 uv=(0,0) でテクセルをサンプルし、白ではなくなる
        var whitePixels = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 { whitePixels += 1 }
            }
        }
        #expect(whitePixels > 100,
                "Shape without UV must stay on the plain fill path (whitePixels=\(whitePixels))")
    }

    @Test("UV follows the vertices through triangleStrip tessellation")
    func triangleStripKeepsUVAlignment() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            texturedQuad(canvas3D, w: w, h: h, size: min(w, h) * 0.6, mode: .triangleStrip)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "red=\(scan.red)")
        #expect(scan.green > 100, "green=\(scan.green)")
        #expect(scan.redMeanX < scan.greenMeanX,
                "Reordering must carry UV with its vertex (redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX))")
    }

    @Test("textured shape larger than the setVertexBytes limit uses the ring buffer")
    func largeTexturedShapeBindsViaRing() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // setVertexBytes は 4096B まで = 48B stride で 85 頂点。三角形ファンで
        // 128 頂点（= 378 頂点へ展開）を描き、リングバッファ経路を通す
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            let cx = w / 2, cy = h / 2, radius = min(w, h) * 0.35
            canvas3D.beginShape(.polygon)
            for i in 0..<128 {
                let a = Float(i) / 128 * 2 * Float.pi
                // u は x に対応させる（左半分 = 赤、右半分 = 緑）
                canvas3D.vertex(cx + cos(a) * radius, cy + sin(a) * radius, 0,
                                (cos(a) + 1) / 2, (sin(a) + 1) / 2)
            }
            canvas3D.endShape(.close)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "red=\(scan.red)")
        #expect(scan.green > 100, "green=\(scan.green)")
        #expect(scan.redMeanX < scan.greenMeanX,
                "redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX)")
    }
}

// MARK: - Canvas3D DynamicMesh UV (#435)

@Suite("Canvas3D DynamicMesh UV", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DDynamicMeshUVTests {

    /// 画面中央に一辺 `size` の quad を組んだ ``DynamicMesh`` を返します（左端 u=0 / 右端 u=1）。
    ///
    /// - Parameters:
    ///   - indexed: true なら 4 頂点 + インデックス、false なら 6 頂点の非インデックス描画。
    ///   - withUV: false なら `addTexCoord` を一度も呼ばない（UV 未宣言のメッシュ）。
    private func quadMesh(device: MTLDevice, w: Float, h: Float, size: Float,
                          indexed: Bool, withUV: Bool = true) -> DynamicMesh {
        let cx = w / 2, cy = h / 2, s = size / 2
        let corners: [(SIMD3<Float>, SIMD2<Float>)] = [
            (SIMD3(cx - s, cy - s, 0), SIMD2(0, 0)),
            (SIMD3(cx + s, cy - s, 0), SIMD2(1, 0)),
            (SIMD3(cx + s, cy + s, 0), SIMD2(1, 1)),
            (SIMD3(cx - s, cy + s, 0), SIMD2(0, 1)),
        ]
        let mesh = DynamicMesh(device: device)
        mesh.addNormal(SIMD3(0, 0, 1))

        if indexed {
            for (position, uv) in corners {
                if withUV { mesh.addTexCoord(uv) }
                mesh.addVertex(position)
            }
            mesh.addTriangle(0, 1, 2)
            mesh.addTriangle(0, 2, 3)
        } else {
            for i in [0, 1, 2, 0, 2, 3] {
                if withUV { mesh.addTexCoord(corners[i].1) }
                mesh.addVertex(corners[i].0)
            }
        }
        return mesh
    }

    /// 白画素（= テクスチャを貼らず fill 色のまま）の個数を数えます。
    private func countWhite(_ pixels: [UInt8], _ texW: Int, _ texH: Int) -> Int {
        var white = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 { white += 1 }
            }
        }
        return white
    }

    @Test("addTexCoord maps the texture across an indexed dynamic mesh")
    func indexedDynamicMeshSamplesTexture() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            // fill は白。UV が効かなければ全面白のまま（テクスチャ色は fill で tint される）
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6, indexed: true)
            canvas3D.dynamicMesh(mesh)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "Left half must sample the red texel (red=\(scan.red))")
        #expect(scan.green > 100, "Right half must sample the green texel (green=\(scan.green))")
        #expect(scan.redMeanX < scan.greenMeanX,
                "u=0 must land left of u=1 (redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX))")
    }

    @Test("UV follows the vertices on the non-indexed draw path")
    func nonIndexedDynamicMeshSamplesTexture() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6, indexed: false)
            canvas3D.dynamicMesh(mesh)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "red=\(scan.red)")
        #expect(scan.green > 100, "green=\(scan.green)")
        #expect(scan.redMeanX < scan.greenMeanX,
                "UV must stay aligned with its vertex (redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX))")
    }

    @Test("texture() without addTexCoord keeps the plain fill path")
    func textureWithoutUVKeepsFillPath() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // UV を宣言していないメッシュはテクスチャ経路へ入れない。誤って入ると
        // 全頂点 uv=(0,0) でテクスチャ左端の赤をサンプルするため白が消える
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)
            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6,
                                indexed: true, withUV: false)
            canvas3D.dynamicMesh(mesh)
        }) else { return }

        #expect(countWhite(pixels, texW, texH) > 100,
                "Mesh without UV must stay on the plain fill path")
    }

    @Test("UV is ignored when no texture is bound")
    func uvWithoutTextureFallsBackToFill() throws {
        let device = MetalTestHelper.device!

        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 0, 0)  // 赤の fill だけで塗られること
            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6, indexed: true)
            canvas3D.dynamicMesh(mesh)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "Mesh must still be filled (red=\(scan.red))")
        #expect(scan.green == 0, "No texture is bound, so no texel color may appear (green=\(scan.green))")
    }

    @Test("setTexCoord respreads the UV of an existing vertex")
    func setTexCoordUpdatesExistingVertex() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // 全頂点 uv=(0,0)（= 一様に赤）で組んでから、右側 2 頂点だけ u=1 へ差し替える。
        // 差し替えが GPU バッファへ反映されなければ緑は 1 画素も出ない
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)

            let cx = w / 2, cy = h / 2, s = min(w, h) * 0.3
            let mesh = DynamicMesh(device: device)
            mesh.addNormal(SIMD3(0, 0, 1))
            mesh.addTexCoord(0, 0)
            mesh.addVertex(cx - s, cy - s, 0)
            mesh.addVertex(cx + s, cy - s, 0)
            mesh.addVertex(cx + s, cy + s, 0)
            mesh.addVertex(cx - s, cy + s, 0)
            mesh.addTriangle(0, 1, 2)
            mesh.addTriangle(0, 2, 3)

            mesh.setTexCoord(1, SIMD2(1, 0))
            mesh.setTexCoord(2, SIMD2(1, 1))

            canvas3D.dynamicMesh(mesh)
        }) else { return }

        let scan = UVTestSupport.scanRedGreen(pixels, texW, texH)
        #expect(scan.red > 100, "red=\(scan.red)")
        #expect(scan.green > 100, "setTexCoord must reach the GPU buffer (green=\(scan.green))")
        #expect(scan.redMeanX < scan.greenMeanX,
                "redMeanX=\(scan.redMeanX), greenMeanX=\(scan.greenMeanX)")
    }

    /// 全面が赤の 1×1 テクスチャ（BGRA8）。
    private func makeRedTexture(device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: [0, 0, 255, 255] as [UInt8], bytesPerRow: 4)
        return MImage(texture: tex)
    }

    @Test("stroke on a textured mesh rebinds the non-UV vertices")
    func strokeOnTexturedMeshUsesPlainVertices() throws {
        let device = MetalTestHelper.device!
        guard let img = makeRedTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // fill でテクスチャ経路（positionNormalUV）へ入ったあと、stroke パスが
        // 通常パイプライン + UV なしの頂点列へ戻さないと線もテクスチャを
        // サンプルしてしまう。赤一色のテクスチャ × 緑の stroke なら
        // 貼り直しに失敗した線は黒（赤 × 緑）になり、緑画素が消える
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            // 塗りを消してワイヤーだけにし、テクスチャ経路からの貼り直しだけを見る
            canvas3D.noFill()
            canvas3D.stroke(0, 255, 0)
            canvas3D.texture(img)
            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6, indexed: true)
            canvas3D.dynamicMesh(mesh)
        }) else { return }

        // ワイヤーは quad の外周に出る。緑（stroke 色）の画素が残っていること
        var greenLine = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                if pixels[i + 1] > 180 && pixels[i + 2] < 120 && pixels[i] < 120 { greenLine += 1 }
            }
        }
        #expect(greenLine > 50, "Stroke must stay in the stroke color (greenLine=\(greenLine))")
    }

    @Test("clear() resets the UV declaration")
    func clearResetsUVDeclaration() throws {
        let device = MetalTestHelper.device!
        guard let img = UVTestSupport.makeHalfRedHalfGreenTexture(device: device) else {
            Issue.record("Failed to create texture")
            return
        }

        // UV 付きで一度組んだメッシュを clear() し、UV なしで組み直す。宣言フラグが
        // 残っていると（前回の pending UV で）テクスチャ経路へ入り白が消える
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noStroke()
            canvas3D.fill(255, 255, 255)
            canvas3D.texture(img)

            let mesh = quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6, indexed: true)
            mesh.ensureBuffers()
            mesh.clear()

            let cx = w / 2, cy = h / 2, s = min(w, h) * 0.3
            mesh.addNormal(SIMD3(0, 0, 1))
            mesh.addVertex(cx - s, cy - s, 0)
            mesh.addVertex(cx + s, cy - s, 0)
            mesh.addVertex(cx + s, cy + s, 0)
            mesh.addTriangle(0, 1, 2)

            canvas3D.dynamicMesh(mesh)
        }) else { return }

        #expect(countWhite(pixels, texW, texH) > 100,
                "clear() must drop the UV declaration and fall back to the plain fill path")
    }
}

// MARK: - DynamicMesh の stroke（#436）

@Suite("Canvas3D DynamicMesh Stroke", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DDynamicMeshStrokeTests {

    /// 画面中央の quad を組んだ ``DynamicMesh``。`color` を渡すと頂点カラーを付けます。
    private func quadMesh(device: MTLDevice, w: Float, h: Float, size: Float,
                          color: SIMD4<Float>? = nil) -> DynamicMesh {
        let cx = w / 2, cy = h / 2, s = size / 2
        let mesh = DynamicMesh(device: device)
        mesh.addNormal(SIMD3(0, 0, 1))
        if let color { mesh.addColor(color) }
        mesh.addVertex(cx - s, cy - s, 0)
        mesh.addVertex(cx + s, cy - s, 0)
        mesh.addVertex(cx + s, cy + s, 0)
        mesh.addVertex(cx - s, cy + s, 0)
        mesh.addTriangle(0, 1, 2)
        mesh.addTriangle(0, 2, 3)
        return mesh
    }

    private func countRedGreenBlue(_ pixels: [UInt8], _ texW: Int, _ texH: Int)
        -> (red: Int, green: Int, blue: Int) {
        var red = 0, green = 0, blue = 0
        for y in 0..<texH {
            for x in 0..<texW {
                let i = (y * texW + x) * 4  // BGRA
                let b = pixels[i], g = pixels[i + 1], r = pixels[i + 2]
                if r > 128 && g < 96 && b < 96 { red += 1 }
                if g > 128 && r < 96 && b < 96 { green += 1 }
                if b > 128 && r < 96 && g < 96 { blue += 1 }
            }
        }
        return (red, green, blue)
    }

    @Test("stroke on a dynamic mesh uses the stroke color, not the vertex color (#436)")
    func strokeColorIgnoresVertexColor() throws {
        let device = MetalTestHelper.device!

        // 頂点カラー赤 × stroke 緑。`wirePipelineState` を通らないと
        // フラグメントは `in.color * uniforms.color` = 黒になり、緑が 1 画素も残らない
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.noFill()
            canvas3D.stroke(0, 255, 0)
            canvas3D.dynamicMesh(quadMesh(device: device, w: w, h: h,
                                          size: min(w, h) * 0.6,
                                          color: SIMD4(1, 0, 0, 1)))
        }) else { return }

        let scan = countRedGreenBlue(pixels, texW, texH)
        #expect(scan.green > 50,
                "Wireframe must be drawn in the stroke color (green=\(scan.green))")
    }

    @Test("stroke stays visible over the fill of the same dynamic mesh (#436)")
    func strokeVisibleOverOwnFill() throws {
        let device = MetalTestHelper.device!

        // fill と stroke は同一ジオメトリを 2 パスで描く。深度バイアスを掛けないと
        // 線は深度比較 `.less` で塗りに負けて 1 本も残らない（#429 と同じ症状）
        guard let (pixels, texW, texH) = try UVTestSupport.render({ canvas3D, w, h in
            canvas3D.fill(0, 0, 255)
            canvas3D.stroke(255, 0, 0)
            canvas3D.dynamicMesh(quadMesh(device: device, w: w, h: h, size: min(w, h) * 0.6))
        }) else { return }

        let scan = countRedGreenBlue(pixels, texW, texH)
        #expect(scan.blue > 100, "Fill must render (blue=\(scan.blue))")
        #expect(scan.red > 50,
                "Stroke must be visible over the fill of the same mesh (red=\(scan.red))")
    }
}

// MARK: - loadPixels の鮮度と順序保証（#158 / #353）

@Suite("Graphics3D loadPixels Freshness", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Graphics3DLoadPixelsFreshnessTests {

    private func makeGraphics3D(
        queue: MTLCommandQueue, width: Int = 400, height: Int = 300
    ) throws -> Graphics3D {
        let device = MetalTestHelper.device!
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        return try Graphics3D(
            device: device,
            commandQueue: queue,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height
        )
    }

    /// 中心付近の画素を返します（box の面の内側を狙う）。
    private func centerPixel(_ img: MImage) -> Color {
        img.loadPixels()
        return img.get(Int(img.width) / 2, Int(img.height) / 2)
    }

    @Test("toImage carries the drawing queue as the readback queue")
    func toImageCarriesReadbackQueue() throws {
        let queue = try #require(MetalTestHelper.commandQueue())
        let pg3d = try makeGraphics3D(queue: queue)
        pg3d.beginDraw()
        pg3d.endDraw()

        let img = pg3d.toImage()
        // リードバックが別キューだと commit 順序が保証されず、endDraw(wait: false)
        // 直後の loadPixels が描画完了前のテクスチャ（＝全黒）を読み得る。
        // CI で Graphics3D 系テストが nonBlackCount = 0 で落ちる flaky の原因（#353）。
        #expect(img.preferredReadbackQueue === queue,
                "toImage() は描画キューをリードバックキューとして引き継ぐ")
    }

    @Test("draw then loadPixels immediately reads the latest content")
    func loadPixelsAfterEndDraw() throws {
        let queue = try #require(MetalTestHelper.commandQueue())
        let pg3d = try makeGraphics3D(queue: queue)

        // 赤い box を unlit（lightCount == 0 で頂点カラーをそのまま出す）で描き、
        // wait なしで終了 → 直後の loadPixels でも最新が読める
        // （リードバックが描画と同じキューに載るため commit 順序で保証される）
        pg3d.beginDraw()
        pg3d.fill(Color(r: 1, g: 0, b: 0, alpha: 1))
        pg3d.translate(200, 150, 0)
        pg3d.box(100)
        pg3d.endDraw(wait: false)

        let img = pg3d.toImage()
        let red = centerPixel(img)
        #expect(red.r > 0.9 && red.g < 0.1, "1 回目の描画結果が読める (got \(red))")

        // 再描画後も最新が読める（ラップテクスチャはピクセルキャッシュを信頼しない）
        pg3d.beginDraw()
        pg3d.fill(Color(r: 0, g: 1, b: 0, alpha: 1))
        pg3d.translate(200, 150, 0)
        pg3d.box(100)
        pg3d.endDraw(wait: false)

        let green = centerPixel(img)
        #expect(green.g > 0.9 && green.r < 0.1,
                "再描画後の loadPixels が古いキャッシュを返さない (got \(green))")
    }
}
