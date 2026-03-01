import Testing
import Metal
import simd
@testable import metaphor

// MARK: - Phase 3: GPU Struct Stride Tests

@Suite("Phase3 GPU Structs")
struct Phase3GPUStructTests {

    @Test("Vertex3DTextured stride is 48 bytes")
    func vertex3DTexturedStride() {
        #expect(MemoryLayout<Vertex3DTextured>.stride == 48)
    }

    @Test("Vertex3DTextured matches positionNormalUV layout stride")
    func vertex3DTexturedMatchesLayout() {
        let layoutStride = VertexLayout.positionNormalUV.makeDescriptor().layouts[0].stride
        #expect(MemoryLayout<Vertex3DTextured>.stride == layoutStride)
    }

    @Test("Light3D stride is 64 bytes")
    func light3DStride() {
        #expect(MemoryLayout<Light3D>.stride == 64)
    }

    @Test("Material3D stride is 48 bytes")
    func material3DStride() {
        #expect(MemoryLayout<Material3D>.stride == 48)
    }
}

// MARK: - Phase 3: Shader Source Tests

@Suite("Phase3 Shader Sources")
struct Phase3ShaderSourceTests {

    @Test("canvas3DSource contains calculateLighting function")
    func canvas3DLightingFn() {
        #expect(BuiltinShaders.canvas3DSource.contains("calculateLighting"))
    }

    @Test("canvas3DTexturedSource contains texture sampling")
    func canvas3DTexturedSampling() {
        #expect(BuiltinShaders.canvas3DTexturedSource.contains("tex.sample"))
    }

    @Test("canvas3DSource contains normalMatrix")
    func canvas3DNormalMatrix() {
        #expect(BuiltinShaders.canvas3DSource.contains("normalMatrix"))
    }

    @Test("canvas3DSource contains cameraPosition")
    func canvas3DCameraPosition() {
        #expect(BuiltinShaders.canvas3DSource.contains("cameraPosition"))
    }

    @Test("canvas3DTexturedSource contains Light3D struct")
    func canvas3DTexturedLight3D() {
        #expect(BuiltinShaders.canvas3DTexturedSource.contains("Light3D"))
    }

    @Test("canvas3DTexturedSource contains Material3D struct")
    func canvas3DTexturedMaterial3D() {
        #expect(BuiltinShaders.canvas3DTexturedSource.contains("Material3D"))
    }

    @Test("FunctionName constants exist in shader source")
    func functionNamesInSource() {
        #expect(BuiltinShaders.canvas3DSource.contains(BuiltinShaders.FunctionName.canvas3DVertex))
        #expect(BuiltinShaders.canvas3DSource.contains(BuiltinShaders.FunctionName.canvas3DFragment))
        #expect(BuiltinShaders.canvas3DTexturedSource.contains(BuiltinShaders.FunctionName.canvas3DTexturedVertex))
        #expect(BuiltinShaders.canvas3DTexturedSource.contains(BuiltinShaders.FunctionName.canvas3DTexturedFragment))
    }
}

// MARK: - Phase 3: Canvas3D Textured Shader Registration

@Suite("Phase3 ShaderLibrary", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Phase3ShaderLibraryTests {

    @Test("canvas3DTextured shader is registered")
    func canvas3DTexturedRegistered() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas3DTextured))
    }

    @Test("can retrieve canvas3DTextured vertex function")
    func texturedVertexFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        #expect(fn != nil)
    }

    @Test("can retrieve canvas3DTextured fragment function")
    func texturedFragmentFn() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let fn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        #expect(fn != nil)
    }

    @Test("textured 3D pipeline can be built")
    func texturedPipelineBuild() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let vfn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        let ffn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        let pipeline = try PipelineFactory(device: device)
            .vertex(vfn)
            .fragment(ffn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .build()
        #expect(pipeline != nil)
    }
}

// MARK: - Phase 3: Mesh UV Tests

@Suite("Phase3 Mesh UVs", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Phase3MeshUVTests {

    @Test("box has UV vertices")
    func boxUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.box(device: device)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount == 24)
    }

    @Test("sphere has UV vertices")
    func sphereUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.sphere(device: device, radius: 1, segments: 8, rings: 4)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount == 45)
    }

    @Test("plane has UV vertices")
    func planeUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.plane(device: device)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount == 4)
    }

    @Test("cylinder has UV vertices")
    func cylinderUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cylinder(device: device, segments: 8)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount > 0)
    }

    @Test("cone has UV vertices")
    func coneUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cone(device: device, segments: 8)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount > 0)
    }

    @Test("torus has UV vertices")
    func torusUVs() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.torus(device: device, segments: 8, tubeSegments: 4)
        #expect(mesh.hasUVs)
        #expect(mesh.uvVertexBuffer != nil)
        #expect(mesh.uvVertexCount == 45)
    }
}

// MARK: - Phase 3: Normal Matrix Tests

@Suite("Phase3 Normal Matrix")
struct Phase3NormalMatrixTests {

    @Test("identity model produces identity normal matrix")
    func identityNormal() {
        let model = float4x4.identity
        let normalMat = testComputeNormalMatrix(from: model)
        for col in 0..<3 {
            for row in 0..<3 {
                let expected: Float = (col == row) ? 1.0 : 0.0
                #expect(abs(normalMat[col][row] - expected) < 0.001)
            }
        }
    }

    @Test("uniform scale produces identity-like normal matrix")
    func uniformScaleNormal() {
        let model = float4x4(scale: 3.0)
        let normalMat = testComputeNormalMatrix(from: model)
        // uniform scale: inverse transpose of 3I = (1/3)I
        let s = normalMat[0][0]
        #expect(abs(s - 1.0 / 3.0) < 0.001)
        #expect(abs(normalMat[1][1] - s) < 0.001)
        #expect(abs(normalMat[2][2] - s) < 0.001)
    }

    @Test("non-uniform scale produces correct normal matrix")
    func nonUniformScaleNormal() {
        let model = float4x4(scale: SIMD3(2, 1, 1))
        let normalMat = testComputeNormalMatrix(from: model)
        // diagonal should be (0.5, 1, 1)
        #expect(abs(normalMat[0][0] - 0.5) < 0.001)
        #expect(abs(normalMat[1][1] - 1.0) < 0.001)
        #expect(abs(normalMat[2][2] - 1.0) < 0.001)
    }

    // Helper: replicates Canvas3D.computeNormalMatrix
    private func testComputeNormalMatrix(from model: float4x4) -> float4x4 {
        let m3 = float3x3(
            SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
            SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
            SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z)
        )
        let invT = m3.inverse.transpose
        return float4x4(columns: (
            SIMD4(invT.columns.0.x, invT.columns.0.y, invT.columns.0.z, 0),
            SIMD4(invT.columns.1.x, invT.columns.1.y, invT.columns.1.z, 0),
            SIMD4(invT.columns.2.x, invT.columns.2.y, invT.columns.2.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}

// MARK: - Phase 3: Material Default Tests

@Suite("Phase3 Material Defaults")
struct Phase3MaterialDefaultTests {

    @Test("default material has ambient 0.2")
    func defaultAmbient() {
        let mat = Material3D.default
        #expect(abs(mat.ambientColor.x - 0.2) < 0.001)
        #expect(abs(mat.ambientColor.y - 0.2) < 0.001)
        #expect(abs(mat.ambientColor.z - 0.2) < 0.001)
    }

    @Test("default material has shininess 32")
    func defaultShininess() {
        #expect(Material3D.default.specularAndShininess.w == 32)
    }

    @Test("default material has zero specular")
    func defaultSpecular() {
        let mat = Material3D.default
        #expect(mat.specularAndShininess.x == 0)
        #expect(mat.specularAndShininess.y == 0)
        #expect(mat.specularAndShininess.z == 0)
    }

    @Test("default material has zero emissive and metallic")
    func defaultEmissiveMetallic() {
        let mat = Material3D.default
        #expect(mat.emissiveAndMetallic == SIMD4(0, 0, 0, 0))
    }
}

// MARK: - Phase 3: Canvas3D Fill/Stroke Unification Tests

@Suite("Phase3 Canvas3D FillStroke", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Phase3Canvas3DFillStrokeTests {

    @Test("Canvas3D noFill does not crash when drawing")
    func noFillNoCrash() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        // noFill → box should not crash (drawMesh early-returns with no encoder)
        canvas3D.noFill()
        canvas3D.box(1)
    }

    @Test("Canvas3D stroke sets wireframe state without crash")
    func strokeNoCrash() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        // stroke → box should not crash (drawMesh early-returns with no encoder)
        canvas3D.stroke(Color.red)
        canvas3D.box(1)
    }

    @Test("Canvas3D noFill + noStroke skips drawing without crash")
    func noFillNoStrokeNoCrash() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.noFill()
        canvas3D.noStroke()
        canvas3D.box(1)
    }

    @Test("Canvas3D fill(gray) can be called")
    func fillGray() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.fill(0.5 as Float)
        canvas3D.box(1)
    }

    @Test("Canvas3D fill(v1,v2,v3) can be called")
    func fillV1V2V3() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.fill(0.2, 0.4, 0.6)
        canvas3D.box(1)
    }

    @Test("Canvas3D stroke(gray) can be called")
    func strokeGray() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.stroke(0.5 as Float)
        canvas3D.box(1)
    }

    @Test("Canvas3D stroke(v1,v2,v3) can be called")
    func strokeV1V2V3() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.stroke(0.2, 0.4, 0.6)
        canvas3D.box(1)
    }

    @Test("Canvas3D colorMode can be set")
    func colorModeSet() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.colorMode(.hsb, 360, 100, 100)
        canvas3D.fill(180, 50, 50)
        canvas3D.box(1)
    }

    @Test("Canvas3D fill(gray, alpha) can be called")
    func fillGrayAlpha() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.fill(0.5 as Float, 0.8 as Float)
        canvas3D.box(1)
    }

    @Test("Canvas3D stroke(gray, alpha) can be called")
    func strokeGrayAlpha() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        canvas3D.stroke(0.5 as Float, 0.8 as Float)
        canvas3D.box(1)
    }

    @Test("SketchContext fill dispatches to both 2D and 3D")
    func sketchContextFillDispatches() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        // Should not crash — dispatches to both canvases
        context.fill(0.5 as Float)
        context.fill(0.2, 0.4, 0.6)
        context.noFill()
    }

    @Test("SketchContext stroke dispatches to both 2D and 3D")
    func sketchContextStrokeDispatches() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        // Should not crash — dispatches to both canvases
        context.stroke(Color.red)
        context.stroke(0.5 as Float)
        context.stroke(0.2, 0.4, 0.6)
        context.noStroke()
    }

    @Test("SketchContext colorMode dispatches to both 2D and 3D")
    func sketchContextColorModeDispatches() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        // Should not crash — dispatches to both canvases
        context.colorMode(.hsb, 360, 100, 100)
        context.fill(180, 50, 50)
    }
}
