import Testing
import Metal
import simd
@testable import metaphor

// MARK: - beginShape Tests

@Suite("beginShape/endShape", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct BeginShapeTests {

    @Test("beginShape and endShape do not crash without encoder")
    func noEncoderSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        // encoder無しでもクラッシュしないことを確認
        canvas.beginShape()
        canvas.vertex(100, 100)
        canvas.vertex(200, 100)
        canvas.vertex(150, 200)
        canvas.endShape(.close)
    }

    @Test("vertex outside beginShape is ignored")
    func vertexOutsideShape() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        // beginShape外のvertexは無視される
        canvas.vertex(100, 100)
        // クラッシュしなければOK
    }

    @Test("all shape modes can be used without crash")
    func allModesSafe() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        let modes: [ShapeMode] = [.polygon, .points, .lines, .triangles, .triangleStrip, .triangleFan]
        for mode in modes {
            canvas.beginShape(mode)
            canvas.vertex(100, 100)
            canvas.vertex(200, 100)
            canvas.vertex(150, 200)
            canvas.vertex(250, 200)
            canvas.endShape()
        }
    }
}

// MARK: - Canvas2D GPU Tests

@Suite("Canvas2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DTests {

    @Test("can create Canvas2D from components")
    func createFromComponents() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }

    @Test("can create Canvas2D from renderer")
    func createFromRenderer() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }
}

// MARK: - Canvas2D currentEncoder Tests

@Suite("Canvas2D Encoder Access", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DEncoderTests {

    @Test("currentEncoder is nil before begin")
    func encoderNilBeforeBegin() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        #expect(canvas.currentEncoder == nil)
    }
}

// MARK: - Canvas3D Shader Tests

@Suite("Canvas3D Shader")
struct Canvas3DShaderTests {

    @Test("canvas3D shader source contains expected function names")
    func shaderFunctions() {
        #expect(BuiltinShaders.canvas3DSource.contains("metaphor_canvas3DVertex"))
        #expect(BuiltinShaders.canvas3DSource.contains("metaphor_canvas3DFragment"))
    }

    @Test("canvas3D shader includes Canvas3DUniforms struct")
    func uniformsStruct() {
        #expect(BuiltinShaders.canvas3DSource.contains("Canvas3DUniforms"))
        #expect(BuiltinShaders.canvas3DSource.contains("normalMatrix"))
        #expect(BuiltinShaders.canvas3DSource.contains("lightCount"))
    }

    @Test("canvas3D shader includes metal_stdlib")
    func metalStdlib() {
        #expect(BuiltinShaders.canvas3DSource.contains("metal_stdlib"))
    }
}

// MARK: - Canvas3D Uniforms Layout Tests

@Suite("Canvas3DUniforms")
struct Canvas3DUniformsTests {

    @Test("Canvas3DUniforms has expected stride (240 bytes)")
    func uniformsStride() {
        let stride = MemoryLayout<Canvas3DUniforms>.stride
        // 3x float4x4(64) + 2x float4(16) + float(4) + 3x uint32(4) + pad = 240
        #expect(stride == 240)
    }

    @Test("modelMatrix is at offset 0")
    func modelMatrixOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.modelMatrix)!
        #expect(offset == 0)
    }

    @Test("viewProjectionMatrix is at offset 64")
    func viewProjectionOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.viewProjectionMatrix)!
        #expect(offset == 64)
    }

    @Test("normalMatrix is at offset 128")
    func normalMatrixOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.normalMatrix)!
        #expect(offset == 128)
    }

    @Test("color is at offset 192")
    func colorOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.color)!
        #expect(offset == 192)
    }

    @Test("cameraPosition is at offset 208")
    func cameraPositionOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.cameraPosition)!
        #expect(offset == 208)
    }

    @Test("time is at offset 224")
    func timeOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.time)!
        #expect(offset == 224)
    }

    @Test("lightCount is at offset 228")
    func lightCountOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.lightCount)!
        #expect(offset == 228)
    }

    @Test("hasTexture is at offset 232")
    func hasTextureOffset() {
        let offset = MemoryLayout<Canvas3DUniforms>.offset(of: \Canvas3DUniforms.hasTexture)!
        #expect(offset == 232)
    }
}

// MARK: - Vertex3D Layout Tests

@Suite("Vertex3D")
struct Vertex3DTests {

    @Test("Vertex3D stride matches positionNormalColor layout")
    func strideMatchesLayout() {
        let stride = MemoryLayout<Vertex3D>.stride
        let expected = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        #expect(stride == expected)  // 48 bytes
    }
}

// MARK: - Canvas3D Tests

@Suite("Canvas3D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DTests {

    @Test("can create Canvas3D from renderer")
    func createFromRenderer() throws {
        let renderer = try MetaphorRenderer()
        let canvas3D = try Canvas3D(renderer: renderer)
        #expect(canvas3D.width == 1920)
        #expect(canvas3D.height == 1080)
    }
}

// MARK: - ShaderLibrary Canvas3D Registration Tests

@Suite("ShaderLibrary Canvas3D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShaderLibraryCanvas3DTests {

    @Test("canvas3D is registered in ShaderLibrary")
    func canvas3DRegistered() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas3D))
    }

    @Test("can retrieve canvas3D vertex function")
    func canvas3DVertexFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        #expect(fn != nil)
    }

    @Test("can retrieve canvas3D fragment function")
    func canvas3DFragmentFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DFragment,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        #expect(fn != nil)
    }
}

// MARK: - Textured Shader Tests

@Suite("Canvas2D Textured Shader", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DTexturedShaderTests {

    @Test("canvas2DTextured shader is registered")
    func registered() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2DTextured))
    }

    @Test("can retrieve textured vertex function")
    func vertexFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        #expect(fn != nil)
    }

    @Test("can retrieve textured fragment function")
    func fragmentFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        #expect(fn != nil)
    }
}

// MARK: - Vertex Layout Tests

@Suite("VertexLayout position2DTexCoordColor")
struct Position2DTexCoordColorTests {

    @Test("stride is 32 bytes")
    func strideCheck() {
        let desc = VertexLayout.position2DTexCoordColor.makeDescriptor()
        #expect(desc.layouts[0].stride == 32)
    }
}
