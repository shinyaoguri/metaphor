import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - VertexLayout Tests

@Suite("VertexLayout")
struct VertexLayoutTests {

    @Test("position layout has correct stride")
    func positionStride() {
        let descriptor = VertexLayout.position.makeDescriptor()
        let stride = descriptor.layouts[0].stride
        #expect(stride == MemoryLayout<SIMD3<Float>>.stride)
    }

    @Test("positionColor layout has correct stride")
    func positionColorStride() {
        let descriptor = VertexLayout.positionColor.makeDescriptor()
        let stride = descriptor.layouts[0].stride
        let expected = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
        #expect(stride == expected)
    }

    @Test("positionNormalColor layout has correct stride")
    func positionNormalColorStride() {
        let descriptor = VertexLayout.positionNormalColor.makeDescriptor()
        let stride = descriptor.layouts[0].stride
        let expected = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        #expect(stride == expected)
    }

    @Test("positionNormalUV layout has correct stride (48 bytes)")
    func positionNormalUVStride() {
        let descriptor = VertexLayout.positionNormalUV.makeDescriptor()
        let stride = descriptor.layouts[0].stride
        let expected = MemoryLayout<SIMD3<Float>>.stride * 3  // 48 bytes (alignment padding)
        #expect(stride == expected)
    }

    @Test("position2DColor layout has correct stride")
    func position2DColorStride() {
        let descriptor = VertexLayout.position2DColor.makeDescriptor()
        let stride = descriptor.layouts[0].stride
        let expected = MemoryLayout<SIMD2<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
        #expect(stride == expected)
    }

    @Test("positionNormalColor attributes have correct offsets")
    func positionNormalColorOffsets() {
        let descriptor = VertexLayout.positionNormalColor.makeDescriptor()
        #expect(descriptor.attributes[0].offset == 0)
        #expect(descriptor.attributes[1].offset == MemoryLayout<SIMD3<Float>>.stride)
        #expect(descriptor.attributes[2].offset == MemoryLayout<SIMD3<Float>>.stride * 2)
    }
}

// MARK: - BlendMode Tests

@Suite("BlendMode")
struct BlendModeTests {

    @Test("opaque disables blending")
    func opaqueMode() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.opaque.apply(to: attachment)
        #expect(attachment.isBlendingEnabled == false)
    }

    @Test("alpha enables blending with correct factors")
    func alphaMode() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.alpha.apply(to: attachment)
        #expect(attachment.isBlendingEnabled == true)
        #expect(attachment.sourceRGBBlendFactor == .sourceAlpha)
        #expect(attachment.destinationRGBBlendFactor == .oneMinusSourceAlpha)
    }

    @Test("additive enables blending with one destination")
    func additiveMode() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.additive.apply(to: attachment)
        #expect(attachment.isBlendingEnabled == true)
        #expect(attachment.sourceRGBBlendFactor == .sourceAlpha)
        #expect(attachment.destinationRGBBlendFactor == .one)
    }

    @Test("multiply uses destination color")
    func multiplyMode() {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.multiply.apply(to: attachment)
        #expect(attachment.isBlendingEnabled == true)
        #expect(attachment.sourceRGBBlendFactor == .destinationColor)
        #expect(attachment.destinationRGBBlendFactor == .zero)
    }

    @Test("all cases are present")
    func allCases() {
        let cases = BlendMode.allCases
        #expect(cases.count == 10)
    }

    @Test("screen blend factor correctness")
    func screenFactors() {
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.screen.apply(to: desc)
        #expect(desc.isBlendingEnabled == true)
        #expect(desc.sourceRGBBlendFactor == .one)
        #expect(desc.destinationRGBBlendFactor == .oneMinusSourceColor)
    }

    @Test("subtract uses reverseSubtract operation")
    func subtractOperation() {
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.subtract.apply(to: desc)
        #expect(desc.isBlendingEnabled == true)
        #expect(desc.rgbBlendOperation == .reverseSubtract)
    }

    @Test("lightest uses max operation")
    func lightestOperation() {
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.lightest.apply(to: desc)
        #expect(desc.isBlendingEnabled == true)
        #expect(desc.rgbBlendOperation == .max)
    }

    @Test("darkest uses min operation")
    func darkestOperation() {
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        BlendMode.darkest.apply(to: desc)
        #expect(desc.isBlendingEnabled == true)
        #expect(desc.rgbBlendOperation == .min)
    }

    @Test("BlendMode is Hashable")
    func hashable() {
        var set: Set<BlendMode> = []
        set.insert(.alpha)
        set.insert(.additive)
        set.insert(.alpha)
        #expect(set.count == 2)
    }
}

// MARK: - BuiltinShaders Tests

@Suite("BuiltinShaders")
struct BuiltinShadersTests {

    @Test("function name constants are non-empty")
    func functionNameConstants() {
        #expect(!BuiltinShaders.FunctionName.blitVertex.isEmpty)
        #expect(!BuiltinShaders.FunctionName.blitFragment.isEmpty)
        #expect(!BuiltinShaders.FunctionName.flatColorVertex.isEmpty)
        #expect(!BuiltinShaders.FunctionName.flatColorFragment.isEmpty)
        #expect(!BuiltinShaders.FunctionName.vertexColorVertex.isEmpty)
        #expect(!BuiltinShaders.FunctionName.vertexColorFragment.isEmpty)
        #expect(!BuiltinShaders.FunctionName.litVertex.isEmpty)
        #expect(!BuiltinShaders.FunctionName.litFragment.isEmpty)
        #expect(!BuiltinShaders.FunctionName.canvas2DVertex.isEmpty)
        #expect(!BuiltinShaders.FunctionName.canvas2DFragment.isEmpty)
    }

    @Test("function name constants have expected values")
    func functionNamesMatchExpected() {
        #expect(BuiltinShaders.FunctionName.blitVertex == "metaphor_blitVertex")
        #expect(BuiltinShaders.FunctionName.blitFragment == "metaphor_blitFragment")
        #expect(BuiltinShaders.FunctionName.flatColorVertex == "metaphor_flatColorVertex")
        #expect(BuiltinShaders.FunctionName.flatColorFragment == "metaphor_flatColorFragment")
        #expect(BuiltinShaders.FunctionName.litVertex == "metaphor_litVertex")
        #expect(BuiltinShaders.FunctionName.litFragment == "metaphor_litFragment")
    }

    @Test("shader resource files can be loaded")
    func shaderResourceFilesExist() {
        #expect(ShaderLibrary.loadShaderSource("blit") != nil)
        #expect(ShaderLibrary.loadShaderSource("flatColor") != nil)
        #expect(ShaderLibrary.loadShaderSource("vertexColor") != nil)
        #expect(ShaderLibrary.loadShaderSource("lit") != nil)
        #expect(ShaderLibrary.loadShaderSource("canvas2D") != nil)
    }

    @Test("shader resource files contain metal_stdlib")
    func shaderResourcesIncludeMetalStdlib() {
        #expect(ShaderLibrary.loadShaderSource("blit")?.contains("#include <metal_stdlib>") == true)
        #expect(ShaderLibrary.loadShaderSource("flatColor")?.contains("#include <metal_stdlib>") == true)
        #expect(ShaderLibrary.loadShaderSource("vertexColor")?.contains("#include <metal_stdlib>") == true)
        #expect(ShaderLibrary.loadShaderSource("lit")?.contains("#include <metal_stdlib>") == true)
        #expect(ShaderLibrary.loadShaderSource("canvas2D")?.contains("#include <metal_stdlib>") == true)
    }
}

// MARK: - GPU-dependent Tests (require Metal device)

@Suite("ShaderLibrary", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShaderLibraryTests {

    @Test("initialization registers all builtin libraries")
    func builtinRegistration() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.blit))
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.flatColor))
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.vertexColor))
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.lit))
        #expect(library.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2D))
    }

    @Test("can retrieve blit vertex function")
    func blitVertexFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let fn = library.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        #expect(fn != nil)
    }

    @Test("can retrieve blit fragment function")
    func blitFragmentFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let fn = library.function(
            named: BuiltinShaders.FunctionName.blitFragment,
            from: ShaderLibrary.BuiltinKey.blit
        )
        #expect(fn != nil)
    }

    @Test("function caching returns same instance")
    func functionCaching() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let fn1 = library.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        let fn2 = library.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        #expect(fn1 === fn2)
    }

    @Test("returns nil for nonexistent function")
    func nonexistentFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let fn = library.function(named: "doesNotExist", from: ShaderLibrary.BuiltinKey.blit)
        #expect(fn == nil)
    }

    @Test("returns nil for nonexistent library")
    func nonexistentLibrary() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let fn = library.function(named: "anything", from: "nonexistent")
        #expect(fn == nil)
    }

    @Test("can register custom shader source")
    func customRegistration() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let customSource = """
        #include <metal_stdlib>
        using namespace metal;

        vertex float4 customVertex(uint vid [[vertex_id]]) {
            return float4(0, 0, 0, 1);
        }
        """

        try library.register(source: customSource, as: "custom")
        #expect(library.hasLibrary(for: "custom"))

        let fn = library.function(named: "customVertex", from: "custom")
        #expect(fn != nil)
    }
}

// MARK: - PipelineFactory GPU Tests

@Suite("PipelineFactory", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PipelineFactoryTests {

    @Test("can build blit pipeline")
    func buildBlitPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let vertexFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        let fragmentFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.blitFragment,
            from: ShaderLibrary.BuiltinKey.blit
        )

        let pipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .build()

        #expect(pipeline.device === device)
    }

    @Test("can build vertex color pipeline with layout")
    func buildVertexColorPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let vertexFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.vertexColorVertex,
            from: ShaderLibrary.BuiltinKey.vertexColor
        )
        let fragmentFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.vertexColorFragment,
            from: ShaderLibrary.BuiltinKey.vertexColor
        )

        let pipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .vertexLayout(.positionNormalColor)
            .build()

        #expect(pipeline.device === device)
    }

    @Test("can build pipeline with alpha blending")
    func buildAlphaBlendPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let vertexFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.vertexColorVertex,
            from: ShaderLibrary.BuiltinKey.vertexColor
        )
        let fragmentFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.vertexColorFragment,
            from: ShaderLibrary.BuiltinKey.vertexColor
        )

        let pipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .build()

        #expect(pipeline.device === device)
    }

    @Test("can build pipeline with functions from ShaderLibrary")
    func buildWithShaderLibraryFunctions() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let vertexFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        let fragmentFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.blitFragment,
            from: ShaderLibrary.BuiltinKey.blit
        )

        let pipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .build()

        #expect(pipeline.device === device)
    }
}

// MARK: - DepthStencilCache GPU Tests

@Suite("DepthStencilCache", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct DepthStencilCacheTests {

    @Test("creates readWrite depth state")
    func readWriteState() {
        let device = MTLCreateSystemDefaultDevice()!
        let cache = DepthStencilCache(device: device)
        let state = cache.state(for: .readWrite)
        #expect(state != nil)
    }

    @Test("creates disabled depth state")
    func disabledState() {
        let device = MTLCreateSystemDefaultDevice()!
        let cache = DepthStencilCache(device: device)
        let state = cache.state(for: .disabled)
        #expect(state != nil)
    }

    @Test("caches same state for repeated calls")
    func cachingBehavior() {
        let device = MTLCreateSystemDefaultDevice()!
        let cache = DepthStencilCache(device: device)
        let state1 = cache.state(for: .readWrite)
        let state2 = cache.state(for: .readWrite)
        #expect(state1 === state2)
    }
}
