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
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 400,
            height: 300
        )
        #expect(pg3d.texture.width == 400)
        #expect(pg3d.texture.height == 300)
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
        pg3d.ambientLight(0.3)
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
        pg3d.fill(Color(r: 1, g: 1, b: 1, a: 1))
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
        pg3d.fill(Color(r: 1, g: 1, b: 1, a: 1))
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
            if shouldClear { canvas2D.clearColorApplied = true }

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
            if shouldClear2 { canvas2D.clearColorApplied = true }

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
