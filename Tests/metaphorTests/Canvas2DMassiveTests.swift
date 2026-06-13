import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - CircleInstance Layout Tests

@Suite("CircleInstance Layout")
struct CircleInstanceLayoutTests {

    @Test("CircleInstance is 32 bytes with 16-byte alignment")
    func layout() {
        #expect(MemoryLayout<CircleInstance>.stride == 32)
        #expect(MemoryLayout<CircleInstance>.alignment == 16)
    }

    @Test("CircleInstance stores position, diameter, and color")
    func fields() {
        let inst = CircleInstance(
            position: SIMD2<Float>(10, 20),
            diameter: 8,
            color: SIMD4<Float>(1, 0, 0, 1)
        )
        #expect(inst.position == SIMD2<Float>(10, 20))
        #expect(inst.diameter == 8)
        #expect(inst.color == SIMD4<Float>(1, 0, 0, 1))
    }
}

// MARK: - Shader Registration

@Suite("Canvas2D Massive Shaders", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas2DMassiveShaderTests {

    @Test("source shader compiles and exposes expected functions")
    func sourceShaderCompiles() throws {
        let device = MetalTestHelper.device!
        let source = try #require(ShaderLibrary.loadShaderSource("canvas2DMassive"))
        let lib = try device.makeLibrary(source: source, options: nil)

        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.circleVertexFunctionName) != nil)
        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.fragmentFunctionName) != nil)
        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.differenceFragmentFunctionName) != nil)
        #expect(lib.makeFunction(name: Canvas2DMassiveShaders.exclusionFragmentFunctionName) != nil)
    }

    @Test("ShaderLibrary registers canvas2DMassive")
    func shaderLibraryRegistration() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()

        #expect(shaderLib.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2DMassive))
        #expect(shaderLib.function(
            named: Canvas2DMassiveShaders.circleVertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DMassive
        ) != nil)
        #expect(shaderLib.function(
            named: Canvas2DMassiveShaders.fragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DMassive
        ) != nil)
    }

    @Test("Canvas2D initializes massive circle pipelines")
    func canvasInitializesPipelines() throws {
        let canvas = try MetalTestHelper.canvas2D(width: 64, height: 64)
        #expect(!canvas.massiveCirclePipelineStates.isEmpty)
    }
}

// MARK: - Render Tests

@Suite("Canvas2D Massive Circles Rendering", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas2DMassiveRenderTests {

    @Test("array circles render per-instance colors")
    func arrayCirclesRender() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.circles([
                CircleInstance(x: 16, y: 32, diameter: 18, color: .red),
                CircleInstance(x: 48, y: 32, diameter: 18, color: .green),
            ])
        }

        let red = helper.readPixel(x: 16, y: 32)
        #expect(red.r > 200 && red.g < 50 && red.b < 50,
                "Expected red circle: R=\(red.r) G=\(red.g) B=\(red.b)")

        let green = helper.readPixel(x: 48, y: 32)
        #expect(green.g > 200 && green.r < 50 && green.b < 50,
                "Expected green circle: R=\(green.r) G=\(green.g) B=\(green.b)")
    }

    @Test("GPUBuffer circles render without CPU staging copy")
    func gpuBufferCirclesRender() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)
        let buffer = try #require(GPUBuffer<CircleInstance>(device: helper.device, data: [
            CircleInstance(x: 32, y: 32, diameter: 24, color: .blue),
        ]))

        try helper.render { canvas in
            canvas.noStroke()
            canvas.circles(buffer)
        }

        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.b > 200 && center.r < 50 && center.g < 50,
                "Expected blue circle: R=\(center.r) G=\(center.g) B=\(center.b)")
    }

    @Test("circles preserve order with regular Canvas2D batches")
    func preservesOrderWithRegularBatches() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.fill(.white)
            canvas.rect(24, 24, 16, 16)
            canvas.circles([
                CircleInstance(x: 32, y: 32, diameter: 28, color: .red),
            ])
            canvas.fill(.green)
            canvas.rect(30, 30, 4, 4)
        }

        let center = helper.readPixel(x: 32, y: 32)
        #expect(center.g > 200 && center.r < 50 && center.b < 50,
                "Last rect should cover circles: R=\(center.r) G=\(center.g) B=\(center.b)")

        let ring = helper.readPixel(x: 32, y: 22)
        #expect(ring.r > 200 && ring.g < 50 && ring.b < 50,
                "Circle should cover earlier rect outside final rect: R=\(ring.r) G=\(ring.g) B=\(ring.b)")
    }

    @Test("circles respect current transform")
    func respectsTransform() throws {
        var helper = try RenderTestHelper(width: 64, height: 64)
        helper.setClearColor(r: 0, g: 0, b: 0)

        try helper.render { canvas in
            canvas.noStroke()
            canvas.translate(10, 0)
            canvas.circles([
                CircleInstance(x: 22, y: 32, diameter: 16, color: .white),
            ])
        }

        let translatedCenter = helper.readPixel(x: 32, y: 32)
        #expect(translatedCenter.r > 200 && translatedCenter.g > 200 && translatedCenter.b > 200)

        let originalCenter = helper.readPixel(x: 22, y: 32)
        #expect(originalCenter.r < 50 && originalCenter.g < 50 && originalCenter.b < 50)
    }
}
