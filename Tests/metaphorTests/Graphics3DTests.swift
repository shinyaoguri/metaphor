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
}
