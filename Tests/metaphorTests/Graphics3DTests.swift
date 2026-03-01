import XCTest
@testable import metaphor

@MainActor
final class Graphics3DTests: XCTestCase {

    // MARK: - Helpers

    private func makeGraphics3D(width: Int = 400, height: Int = 300) -> Graphics3D? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        guard let shaderLib = try? ShaderLibrary(device: device) else { return nil }
        let depthCache = DepthStencilCache(device: device)
        return try? Graphics3D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height
        )
    }

    // MARK: - Creation Tests

    func testCreation() {
        let pg3d = makeGraphics3D()
        XCTAssertNotNil(pg3d)
    }

    func testDimensions() {
        let pg3d = makeGraphics3D(width: 800, height: 600)
        XCTAssertNotNil(pg3d)
        XCTAssertEqual(pg3d!.width, 800)
        XCTAssertEqual(pg3d!.height, 600)
    }

    func testTextureExists() {
        let pg3d = makeGraphics3D()
        XCTAssertNotNil(pg3d)
        XCTAssertNotNil(pg3d!.texture)
        XCTAssertEqual(pg3d!.texture.width, 400)
        XCTAssertEqual(pg3d!.texture.height, 300)
    }

    // MARK: - Lifecycle Tests

    func testBeginEndDraw() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
        // beginDraw → endDraw が安全に呼べる
        pg3d.beginDraw()
        pg3d.endDraw()
    }

    func testToImage() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
        pg3d.beginDraw()
        pg3d.endDraw()
        let img = pg3d.toImage()
        XCTAssertEqual(img.width, 400)
        XCTAssertEqual(img.height, 300)
    }

    func testDrawPrimitives() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
        pg3d.beginDraw()
        pg3d.lights()
        pg3d.fill(.red)
        pg3d.box(100)
        pg3d.endDraw()
        // クラッシュしなければ OK
    }

    func testMultipleDrawCycles() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
        // 複数回描画できる
        for _ in 0..<3 {
            pg3d.beginDraw()
            pg3d.fill(.blue)
            pg3d.sphere(50)
            pg3d.endDraw()
        }
    }

    func testTransformMethods() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
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
    }

    func testCameraAndLighting() {
        guard let pg3d = makeGraphics3D() else {
            return
        }
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
    }
}
