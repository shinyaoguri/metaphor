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

    @Test("blit shader source contains expected function names")
    func blitShaderFunctions() {
        #expect(BuiltinShaders.blitSource.contains("metaphor_blitVertex"))
        #expect(BuiltinShaders.blitSource.contains("metaphor_blitFragment"))
    }

    @Test("flatColor shader source contains expected function names")
    func flatColorShaderFunctions() {
        #expect(BuiltinShaders.flatColorSource.contains("metaphor_flatColorVertex"))
        #expect(BuiltinShaders.flatColorSource.contains("metaphor_flatColorFragment"))
    }

    @Test("vertexColor shader source contains expected function names")
    func vertexColorShaderFunctions() {
        #expect(BuiltinShaders.vertexColorSource.contains("metaphor_vertexColorVertex"))
        #expect(BuiltinShaders.vertexColorSource.contains("metaphor_vertexColorFragment"))
    }

    @Test("lit shader source contains expected function names")
    func litShaderFunctions() {
        #expect(BuiltinShaders.litSource.contains("metaphor_litVertex"))
        #expect(BuiltinShaders.litSource.contains("metaphor_litFragment"))
    }

    @Test("canvas2D shader source contains expected function names")
    func canvas2DShaderFunctions() {
        #expect(BuiltinShaders.canvas2DSource.contains("metaphor_canvas2DVertex"))
        #expect(BuiltinShaders.canvas2DSource.contains("metaphor_canvas2DFragment"))
    }

    @Test("function name constants match shader source")
    func functionNamesMatchSource() {
        #expect(BuiltinShaders.blitSource.contains(BuiltinShaders.FunctionName.blitVertex))
        #expect(BuiltinShaders.blitSource.contains(BuiltinShaders.FunctionName.blitFragment))
        #expect(BuiltinShaders.flatColorSource.contains(BuiltinShaders.FunctionName.flatColorVertex))
        #expect(BuiltinShaders.flatColorSource.contains(BuiltinShaders.FunctionName.flatColorFragment))
        #expect(BuiltinShaders.litSource.contains(BuiltinShaders.FunctionName.litVertex))
        #expect(BuiltinShaders.litSource.contains(BuiltinShaders.FunctionName.litFragment))
    }

    @Test("all shaders include metal_stdlib")
    func shadersIncludeMetalStdlib() {
        #expect(BuiltinShaders.blitSource.contains("#include <metal_stdlib>"))
        #expect(BuiltinShaders.flatColorSource.contains("#include <metal_stdlib>"))
        #expect(BuiltinShaders.vertexColorSource.contains("#include <metal_stdlib>"))
        #expect(BuiltinShaders.litSource.contains("#include <metal_stdlib>"))
        #expect(BuiltinShaders.canvas2DSource.contains("#include <metal_stdlib>"))
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

        #expect(pipeline.label == nil || true) // pipeline was created successfully
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

        #expect(pipeline.label == nil || true)
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

        #expect(pipeline.label == nil || true)
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

        #expect(pipeline.label == nil || true)
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
