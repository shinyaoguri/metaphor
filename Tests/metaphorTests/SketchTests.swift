import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - SketchConfig Tests

@Suite("SketchConfig")
struct SketchConfigTests {

    @Test("default config values")
    func defaultValues() {
        let config = SketchConfig()
        #expect(config.width == 1920)
        #expect(config.height == 1080)
        #expect(config.title == "metaphor")
        #expect(config.fps == 60)
        #expect(config.syphonName == nil)
        #expect(config.windowScale == 0.5)
    }

    @Test("custom config values")
    func customValues() {
        let config = SketchConfig(
            width: 1280,
            height: 720,
            title: "Test",
            fps: 30,
            syphonName: "TestSyphon",
            windowScale: 1.0
        )
        #expect(config.width == 1280)
        #expect(config.height == 720)
        #expect(config.title == "Test")
        #expect(config.fps == 30)
        #expect(config.syphonName == "TestSyphon")
        #expect(config.windowScale == 1.0)
    }
}

// MARK: - SketchContext Tests

@Suite("SketchContext", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextTests {

    @Test("context has correct dimensions")
    func dimensions() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.width == 1920)
        #expect(context.height == 1080)
    }

    @Test("context initial state")
    func initialState() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.time == 0)
        #expect(context.deltaTime == 0)
        #expect(context.frameCount == 0)
    }

    @Test("context exposes renderer")
    func escapteHatch() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.renderer === renderer)
        #expect(context.canvas === canvas)
        #expect(context.input === renderer.input)
    }

    @Test("context encoder is nil outside frame")
    func encoderOutsideFrame() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.encoder == nil)
    }
}

// MARK: - SketchContext Compute Tests

@Suite("SketchContext Compute", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextComputeTests {

    @Test("createComputeKernel compiles MSL source")
    func createKernel() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void test(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 1.0;
        }
        """
        let kernel = try context.createComputeKernel(source: source, function: "test")
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
    }

    @Test("createBuffer creates typed GPU buffer")
    func createTypedBuffer() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let buf = context.createBuffer(count: 100, type: Float.self)
        #expect(buf != nil)
        #expect(buf!.count == 100)
    }

    @Test("createBuffer from array preserves data")
    func createBufferFromArray() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let data: [Float] = [1, 2, 3, 4, 5]
        let buf = context.createBuffer(data)
        #expect(buf != nil)
        #expect(buf![2] == 3.0)
    }
}
