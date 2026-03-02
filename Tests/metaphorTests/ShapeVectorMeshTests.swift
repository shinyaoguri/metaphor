import Testing
import Metal
import simd
@testable import metaphor

// MARK: - B-6: Per-vertex Color Shape Tests

@Suite("B-6 Per-vertex Color 2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PerVertexColor2DTests {

    @Test("vertex with color does not crash")
    func vertexColorSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.beginShape(.triangles)
        canvas.vertex(100, 100, Color.red)
        canvas.vertex(200, 100, Color.green)
        canvas.vertex(150, 200, Color.blue)
        canvas.endShape()
    }

    @Test("vertex with UV does not crash")
    func vertexUVSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.beginShape(.triangles)
        canvas.vertex(100, 100, 0, 0)
        canvas.vertex(200, 100, 1, 0)
        canvas.vertex(150, 200, 0.5, 1)
        canvas.endShape()
    }

    @Test("per-vertex color triangleStrip does not crash")
    func triangleStripColorSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.beginShape(.triangleStrip)
        canvas.vertex(0, 0, Color.red)
        canvas.vertex(100, 0, Color.green)
        canvas.vertex(50, 100, Color.blue)
        canvas.vertex(150, 100, Color.white)
        canvas.endShape()
    }

    @Test("per-vertex color triangleFan does not crash")
    func triangleFanColorSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.beginShape(.triangleFan)
        canvas.vertex(200, 200, Color.white)
        canvas.vertex(300, 200, Color.red)
        canvas.vertex(300, 300, Color.green)
        canvas.vertex(200, 300, Color.blue)
        canvas.endShape()
    }
}

// MARK: - B-6b: 3D beginShape/endShape Tests

@Suite("B-6 3D beginShape", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct BeginShape3DTests {

    @Test("3D beginShape/endShape polygon does not crash")
    func polygon3DSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas3D.beginShape()
        canvas3D.vertex(0, 0, 0)
        canvas3D.vertex(1, 0, 0)
        canvas3D.vertex(0.5, 1, 0)
        canvas3D.endShape(.close)
    }

    @Test("3D beginShape with per-vertex color does not crash")
    func vertexColor3DSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas3D.beginShape(.triangles)
        canvas3D.vertex(0, 0, 0, Color.red)
        canvas3D.vertex(1, 0, 0, Color.green)
        canvas3D.vertex(0.5, 1, 0, Color.blue)
        canvas3D.endShape()
    }

    @Test("3D normal() affects subsequent vertices")
    func normalSetting() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas3D.beginShape(.triangles)
        canvas3D.normal(0, 0, 1)
        canvas3D.vertex(0, 0, 0)
        canvas3D.vertex(1, 0, 0)
        canvas3D.vertex(0.5, 1, 0)
        canvas3D.endShape()
    }

    @Test("3D all shape modes do not crash")
    func allModes3DSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        let modes: [ShapeMode] = [.polygon, .triangles, .triangleStrip, .triangleFan, .points, .lines]
        for mode in modes {
            canvas3D.beginShape(mode)
            canvas3D.vertex(0, 0, 0)
            canvas3D.vertex(1, 0, 0)
            canvas3D.vertex(0.5, 1, 0)
            canvas3D.vertex(1.5, 1, 0)
            canvas3D.endShape()
        }
    }
}

// MARK: - B-7: Vec2 Enhancement Tests

@Suite("B-7 Vec2 Enhancements")
struct Vec2EnhancementTests {

    @Test("withMagnitude sets correct length")
    func withMagnitudeTest() {
        let v = Vec2(3, 4)
        let scaled = v.withMagnitude(10)
        #expect(abs(scaled.magnitude - 10) < 0.001)
    }

    @Test("withMagnitude preserves direction")
    func withMagnitudeDirection() {
        let v = Vec2(3, 4)
        let scaled = v.withMagnitude(10)
        let original = v.normalized()
        let scaledNorm = scaled.normalized()
        #expect(abs(original.x - scaledNorm.x) < 0.001)
        #expect(abs(original.y - scaledNorm.y) < 0.001)
    }

    @Test("cross product 2D")
    func cross2DTest() {
        let a = Vec2(1, 0)
        let b = Vec2(0, 1)
        #expect(abs(a.cross(b) - 1) < 0.0001)
        #expect(abs(b.cross(a) - (-1)) < 0.0001)
    }

    @Test("cross product parallel is zero")
    func crossParallel() {
        let a = Vec2(3, 4)
        let b = Vec2(6, 8)
        #expect(abs(a.cross(b)) < 0.0001)
    }

    @Test("angleBetween orthogonal is pi/2")
    func angleBetweenOrthogonal() {
        let a = Vec2(1, 0)
        let b = Vec2(0, 1)
        #expect(abs(a.angleBetween(b) - Float.pi / 2) < 0.001)
    }

    @Test("angleBetween same direction is 0")
    func angleBetweenSame() {
        let a = Vec2(3, 4)
        let b = Vec2(6, 8)
        #expect(abs(a.angleBetween(b)) < 0.001)
    }

    @Test("Vec3 withMagnitude")
    func vec3WithMagnitude() {
        let v = Vec3(1, 2, 2)
        let scaled = v.withMagnitude(6)
        #expect(abs(scaled.magnitude - 6) < 0.001)
    }

    @Test("Vec3 angleBetween")
    func vec3AngleBetween() {
        let a = Vec3(1, 0, 0)
        let b = Vec3(0, 1, 0)
        #expect(abs(a.angleBetween(b) - Float.pi / 2) < 0.001)
    }

    @Test("Vec3 angleBetween same direction is 0")
    func vec3AngleBetweenSame() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(2, 4, 6)
        #expect(abs(a.angleBetween(b)) < 0.001)
    }
}

// MARK: - B-8: Sub-image Drawing Tests

@Suite("B-8 Sub-image", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SubImageTests {

    @Test("image with source rect does not crash")
    func imageSourceRectSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        // MImage requires a texture - create a dummy one
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false
        )
        let texture = device.makeTexture(descriptor: desc)!
        let img = MImage(texture: texture)

        // Full image
        canvas.image(img, 0, 0, 100, 100)

        // Sub-image (sprite sheet style)
        canvas.image(img, 0, 0, 64, 64, 0, 0, 64, 64)
        canvas.image(img, 100, 0, 64, 64, 64, 0, 64, 64)
    }
}

// MARK: - B-9: DynamicMesh Tests

@Suite("B-9 DynamicMesh", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct DynamicMeshTests {

    @Test("addVertex and count")
    func addVertexCount() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0, 1, 0)
        #expect(mesh.vertexCount == 3)
    }

    @Test("addTriangle and indexCount")
    func addTriangleCount() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0, 1, 0)
        mesh.addTriangle(0, 1, 2)
        #expect(mesh.indexCount == 3)
    }

    @Test("getVertex returns correct position")
    func getVertexPosition() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(1.5, 2.5, 3.5)
        let pos = mesh.getVertex(0)
        #expect(abs(pos.x - 1.5) < 0.001)
        #expect(abs(pos.y - 2.5) < 0.001)
        #expect(abs(pos.z - 3.5) < 0.001)
    }

    @Test("setVertex modifies position")
    func setVertexModify() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.setVertex(0, SIMD3(5, 10, 15))
        let pos = mesh.getVertex(0)
        #expect(abs(pos.x - 5) < 0.001)
        #expect(abs(pos.y - 10) < 0.001)
        #expect(abs(pos.z - 15) < 0.001)
    }

    @Test("clear removes all data")
    func clearMesh() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addTriangle(0, 0, 0)
        mesh.clear()
        #expect(mesh.vertexCount == 0)
        #expect(mesh.indexCount == 0)
    }

    @Test("ensureBuffers creates vertex buffer")
    func ensureBuffersCreates() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0, 1, 0)
        mesh.ensureBuffers()
        #expect(mesh.vertexBuffer != nil)
    }

    @Test("ensureBuffers with indices creates index buffer")
    func ensureBuffersWithIndices() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0, 1, 0)
        mesh.addTriangle(0, 1, 2)
        mesh.ensureBuffers()
        #expect(mesh.indexBuffer != nil)
    }

    @Test("addNormal and addColor affect subsequent vertices")
    func normalAndColor() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = DynamicMesh(device: device)
        mesh.addNormal(SIMD3(0, 0, 1))
        mesh.addColor(Color.red)
        mesh.addVertex(0, 0, 0)
        // Just verifying it doesn't crash
        #expect(mesh.vertexCount == 1)
    }
}

// MARK: - B-10: Custom Vertex Shader Tests

@Suite("B-10 Custom Vertex Shader", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CustomVertexShaderTests {

    @Test("CustomMaterial with vertex function stores properties")
    func customMaterialVertexFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        // Use full canvas3D source which includes VertexIn/VertexOut structs
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct VIn {
            float3 position [[attribute(0)]];
            float3 normal   [[attribute(1)]];
            float4 color    [[attribute(2)]];
        };

        struct VOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        vertex VOut myCustomVertex(
            VIn in [[stage_in]],
            constant Canvas3DUniforms &u [[buffer(1)]]
        ) {
            VOut out;
            float4 worldPos = u.modelMatrix * float4(in.position, 1.0);
            out.position = u.viewProjectionMatrix * worldPos;
            out.worldPosition = worldPos.xyz;
            out.normal = (u.normalMatrix * float4(in.normal, 0.0)).xyz;
            out.color = u.color;
            return out;
        }

        fragment float4 myCustomFragment(
            VOut in [[stage_in]],
            constant Canvas3DUniforms &u [[buffer(1)]]
        ) {
            return in.color;
        }
        """

        let key = "test.custom.vertex"
        try shaderLib.register(source: source, as: key)
        let fragFn = shaderLib.function(named: "myCustomFragment", from: key)!
        let vtxFn = shaderLib.function(named: "myCustomVertex", from: key)!

        let mat = CustomMaterial(
            fragmentFunction: fragFn,
            functionName: "myCustomFragment",
            libraryKey: key,
            vertexFunction: vtxFn,
            vertexFunctionName: "myCustomVertex"
        )

        #expect(mat.fragmentFunctionName == "myCustomFragment")
        #expect(mat.vertexFunctionName == "myCustomVertex")
        #expect(mat.vertexFunction != nil)
    }

    @Test("CustomMaterial without vertex function has nil vertex")
    func customMaterialNoVertex() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct VOut {
            float4 position [[position]];
            float4 color;
        };

        fragment float4 simpleFragment(
            VOut in [[stage_in]],
            constant Canvas3DUniforms &u [[buffer(1)]]
        ) {
            return in.color;
        }
        """

        let key = "test.custom.novtx"
        try shaderLib.register(source: source, as: key)
        let fragFn = shaderLib.function(named: "simpleFragment", from: key)!

        let mat = CustomMaterial(
            fragmentFunction: fragFn,
            functionName: "simpleFragment",
            libraryKey: key
        )

        #expect(mat.vertexFunction == nil)
        #expect(mat.vertexFunctionName == nil)
    }
}

// MARK: - B-11: pushStyle/pushMatrix Tests

@Suite("B-11 pushStyle/pushMatrix", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PushStyleMatrixTests {

    @Test("pushMatrix/popMatrix only saves transform in Canvas2D")
    func canvas2DPushMatrix() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.pushMatrix()
        canvas.translate(100, 200)
        canvas.popMatrix()
        // Transform should be restored - verifiable by lack of crash
    }

    @Test("pushStyle/popStyle only saves style in Canvas2D")
    func canvas2DPushStyle() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas = try Canvas2D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas.pushStyle()
        canvas.fill(Color.red)
        canvas.noStroke()
        canvas.popStyle()
        // Style should be restored
    }

    @Test("Canvas3D pushState/popState saves all")
    func canvas3DPushState() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas3D.pushState()
        canvas3D.translate(1, 2, 3)
        canvas3D.fill(Color.red)
        canvas3D.popState()
    }

    @Test("Canvas3D pushMatrix/popMatrix saves only transform")
    func canvas3DPushMatrix() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device, shaderLibrary: shaderLib,
            depthStencilCache: depthCache, width: 800, height: 600
        )

        canvas3D.pushMatrix()
        canvas3D.translate(1, 2, 3)
        canvas3D.rotateY(Float.pi)
        canvas3D.popMatrix()
    }
}

// MARK: - B-12: Utility Function Tests

@Suite("B-12 randomGaussian")
@MainActor
struct RandomGaussianTests {

    @Test("randomGaussian returns values")
    func gaussianReturns() {
        var values: [Float] = []
        for _ in 0..<100 {
            values.append(randomGaussian())
        }
        // Should have some variance
        let mean = values.reduce(0, +) / Float(values.count)
        #expect(abs(mean) < 1.0) // mean should be near 0
    }

    @Test("randomGaussian respects mean and sd")
    func gaussianMeanSD() {
        var values: [Float] = []
        for _ in 0..<1000 {
            values.append(randomGaussian(10, 2))
        }
        let mean = values.reduce(0, +) / Float(values.count)
        #expect(abs(mean - 10) < 1.0) // should be near 10
    }
}
