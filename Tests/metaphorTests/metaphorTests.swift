import Testing
import Metal
import simd
@testable import metaphor

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
        #expect(cases.count == 8)
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

// MARK: - Math Utility Tests

@Suite("Math Utilities")
struct MathUtilityTests {

    @Test("radians conversion")
    func radiansConversion() {
        let result = radians(180)
        #expect(abs(result - Float.pi) < 0.0001)
    }

    @Test("degrees conversion")
    func degreesConversion() {
        let result = degrees(Float.pi)
        #expect(abs(result - 180) < 0.0001)
    }

    @Test("lerp at boundaries")
    func lerpBoundaries() {
        #expect(lerp(Float(0), Float(10), Float(0)) == 0)
        #expect(lerp(Float(0), Float(10), Float(1)) == 10)
        #expect(lerp(Float(0), Float(10), Float(0.5)) == 5)
    }

    @Test("saturate clamps correctly")
    func saturateClamp() {
        #expect(saturate(-0.5) == 0)
        #expect(saturate(0.5) == 0.5)
        #expect(saturate(1.5) == 1)
    }

    @Test("smoothstep at boundaries")
    func smoothstepBoundaries() {
        #expect(smoothstep(0, 1, 0) == 0)
        #expect(smoothstep(0, 1, 1) == 1)
        let mid = smoothstep(0, 1, 0.5)
        #expect(abs(mid - 0.5) < 0.01)
    }

    @Test("identity matrix")
    func identityMatrix() {
        let id = float4x4.identity
        #expect(id.columns.0 == SIMD4<Float>(1, 0, 0, 0))
        #expect(id.columns.1 == SIMD4<Float>(0, 1, 0, 0))
        #expect(id.columns.2 == SIMD4<Float>(0, 0, 1, 0))
        #expect(id.columns.3 == SIMD4<Float>(0, 0, 0, 1))
    }

    @Test("translation matrix")
    func translationMatrix() {
        let t = float4x4(translation: SIMD3<Float>(1, 2, 3))
        #expect(t.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    }

    @Test("uniform scale matrix")
    func uniformScaleMatrix() {
        let s = float4x4(scale: Float(2))
        #expect(s.columns.0.x == 2)
        #expect(s.columns.1.y == 2)
        #expect(s.columns.2.z == 2)
        #expect(s.columns.3.w == 1)
    }
}

// MARK: - Time Utility Tests

@Suite("Time Utilities")
struct TimeUtilityTests {

    @Test("sine01 returns values in 0-1 range")
    func sine01Range() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = sine01(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("triangle returns values in 0-1 range")
    func triangleRange() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = triangle(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("sawtooth returns values in 0-1 range")
    func sawtoothRange() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = sawtooth(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("square returns 0 or 1")
    func squareValues() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = square(t)
            #expect(v == 0 || v == 1)
        }
    }
}

// MARK: - Color Tests

@Suite("Color")
struct ColorTests {

    @Test("RGB init stores correct components")
    func rgbInit() {
        let c = Color(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        #expect(c.r == 0.2)
        #expect(c.g == 0.4)
        #expect(c.b == 0.6)
        #expect(c.a == 0.8)
    }

    @Test("RGB init defaults alpha to 1")
    func rgbDefaultAlpha() {
        let c = Color(r: 1, g: 0, b: 0)
        #expect(c.a == 1.0)
    }

    @Test("grayscale init sets equal RGB")
    func grayInit() {
        let c = Color(gray: 0.5)
        #expect(c.r == 0.5)
        #expect(c.g == 0.5)
        #expect(c.b == 0.5)
        #expect(c.a == 1.0)
    }

    @Test("HSB pure red")
    func hsbRed() {
        let c = Color(hue: 0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 1.0) < 0.001)
        #expect(abs(c.g - 0.0) < 0.001)
        #expect(abs(c.b - 0.0) < 0.001)
    }

    @Test("HSB pure green")
    func hsbGreen() {
        let c = Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 0.0) < 0.001)
        #expect(abs(c.g - 1.0) < 0.001)
        #expect(abs(c.b - 0.0) < 0.001)
    }

    @Test("HSB pure blue")
    func hsbBlue() {
        let c = Color(hue: 2.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 0.0) < 0.001)
        #expect(abs(c.g - 0.0) < 0.001)
        #expect(abs(c.b - 1.0) < 0.001)
    }

    @Test("HSB zero saturation gives gray")
    func hsbGray() {
        let c = Color(hue: 0.5, saturation: 0, brightness: 0.7)
        #expect(abs(c.r - 0.7) < 0.001)
        #expect(abs(c.g - 0.7) < 0.001)
        #expect(abs(c.b - 0.7) < 0.001)
    }

    @Test("hex 0xRRGGBB")
    func hexRGB() {
        let c = Color(hex: 0xFF8000)
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.502) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
        #expect(c.a == 1.0)
    }

    @Test("hex 0xAARRGGBB")
    func hexARGB() {
        let c = Color(hex: 0x80FF0000)
        #expect(abs(c.a - 0.502) < 0.01)
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
    }

    @Test("hex string parsing")
    func hexString() {
        let c = Color(hex: "#FF0000")
        #expect(c != nil)
        #expect(c!.r == 1.0)
        #expect(c!.g == 0.0)
        #expect(c!.b == 0.0)
    }

    @Test("hex string invalid returns nil")
    func hexStringInvalid() {
        let c = Color(hex: "not-a-hex")
        #expect(c == nil)
    }

    @Test("SIMD conversion roundtrip")
    func simdConversion() {
        let original = Color(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        let reconstructed = Color(original.simd)
        #expect(original == reconstructed)
    }

    @Test("withAlpha returns new color")
    func withAlpha() {
        let c = Color.red.withAlpha(0.5)
        #expect(c.r == 1.0)
        #expect(c.a == 0.5)
    }

    @Test("lerp between colors")
    func lerpColors() {
        let a = Color.black
        let b = Color.white
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.r - 0.5) < 0.001)
        #expect(abs(mid.g - 0.5) < 0.001)
        #expect(abs(mid.b - 0.5) < 0.001)
    }

    @Test("named colors are correct")
    func namedColors() {
        #expect(Color.black == Color(gray: 0))
        #expect(Color.white == Color(gray: 1))
        #expect(Color.red == Color(r: 1, g: 0, b: 0))
        #expect(Color.green == Color(r: 0, g: 1, b: 0))
        #expect(Color.blue == Color(r: 0, g: 0, b: 1))
        #expect(Color.clear.a == 0)
    }

    @Test("clearColor conversion")
    func clearColorConversion() {
        let c = Color(r: 0.5, g: 0.25, b: 0.75, a: 1.0)
        let cc = c.clearColor
        #expect(abs(cc.red - 0.5) < 0.001)
        #expect(abs(cc.green - 0.25) < 0.001)
        #expect(abs(cc.blue - 0.75) < 0.001)
    }
}

// MARK: - Noise Tests

@Suite("NoiseGenerator")
struct NoiseTests {

    @Test("1D noise output in 0..1 range")
    func noise1DRange() {
        let gen = NoiseGenerator()
        for i in 0..<100 {
            let x = Float(i) * 0.1
            let v = gen.noise(x)
            #expect(v >= 0 && v <= 1, "noise(\(x)) = \(v) out of range")
        }
    }

    @Test("2D noise output in 0..1 range")
    func noise2DRange() {
        let gen = NoiseGenerator()
        for i in 0..<50 {
            for j in 0..<50 {
                let x = Float(i) * 0.1
                let y = Float(j) * 0.1
                let v = gen.noise(x, y)
                #expect(v >= 0 && v <= 1)
            }
        }
    }

    @Test("3D noise output in 0..1 range")
    func noise3DRange() {
        let gen = NoiseGenerator()
        for i in 0..<20 {
            let x = Float(i) * 0.1
            let v = gen.noise(x, x * 0.7, x * 1.3)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("noise is deterministic")
    func noiseDeterministic() {
        let gen = NoiseGenerator()
        let v1 = gen.noise(1.5, 2.3)
        let v2 = gen.noise(1.5, 2.3)
        #expect(v1 == v2)
    }

    @Test("different seeds produce different output")
    func noiseSeedDifference() {
        let gen0 = NoiseGenerator(seed: 0)
        let gen1 = NoiseGenerator(seed: 42)
        // 非整数座標を使う（整数座標ではPerlinノイズは常に0）
        let v0 = gen0.noise(1.3, 2.7)
        let v1 = gen1.noise(1.3, 2.7)
        #expect(v0 != v1)
    }

    @Test("noise varies spatially")
    func noiseSpatialVariation() {
        let gen = NoiseGenerator()
        var values: Set<Int> = []
        for i in 0..<10 {
            // 非整数座標を使う
            let v = gen.noise(Float(i) * 0.73 + 0.1)
            values.insert(Int(v * 1000))
        }
        #expect(values.count > 3, "noise should produce varied output")
    }

    @Test("octaves affect output")
    func noiseOctaves() {
        var gen1 = NoiseGenerator()
        gen1.octaves = 1
        var gen4 = NoiseGenerator()
        gen4.octaves = 4

        // With different octaves, the output should differ at most points
        var diffs = 0
        for i in 0..<20 {
            let x = Float(i) * 0.5
            if abs(gen1.noise(x) - gen4.noise(x)) > 0.001 {
                diffs += 1
            }
        }
        #expect(diffs > 5, "different octave counts should produce different results")
    }
}

// MARK: - MathUtils Tests

@Suite("MathUtils")
struct MathUtilsTests {

    @Test("map linear range")
    func mapLinear() {
        #expect(map(5, 0, 10, 0, 100) == 50)
        #expect(map(0, 0, 10, 100, 200) == 100)
        #expect(map(10, 0, 10, 100, 200) == 200)
    }

    @Test("map with negative ranges")
    func mapNegative() {
        let result = map(0, -10, 10, 0, 100)
        #expect(abs(result - 50) < 0.0001)
    }

    @Test("constrain clamps within range")
    func constrainClamp() {
        #expect(constrain(5, 0, 10) == 5)
        #expect(constrain(-5, 0, 10) == 0)
        #expect(constrain(15, 0, 10) == 10)
    }

    @Test("norm normalizes to 0-1")
    func normRange() {
        #expect(norm(5, 0, 10) == 0.5)
        #expect(norm(0, 0, 10) == 0)
        #expect(norm(10, 0, 10) == 1)
    }

    @Test("dist 2D")
    func dist2D() {
        #expect(dist(0, 0, 3, 4) == 5)
        #expect(dist(0, 0, 0, 0) == 0)
    }

    @Test("dist 3D")
    func dist3D() {
        let d = dist(0, 0, 0, 1, 1, 1)
        #expect(abs(d - sqrt(Float(3))) < 0.0001)
    }

    @Test("sq returns square")
    func sqTest() {
        #expect(sq(3) == 9)
        #expect(sq(-4) == 16)
    }

    @Test("mag 2D")
    func mag2D() {
        #expect(mag(3, 4) == 5)
    }
}

// MARK: - Random Tests

@Suite("Random")
@MainActor
struct RandomTests {

    @Test("random with high returns value in range")
    func randomHighRange() {
        for _ in 0..<100 {
            let v = random(Float(10))
            #expect(v >= 0 && v < 10)
        }
    }

    @Test("random with low and high returns value in range")
    func randomLowHighRange() {
        for _ in 0..<100 {
            let v = random(Float(5), Float(15))
            #expect(v >= 5 && v < 15)
        }
    }

    @Test("randomSeed produces deterministic sequence")
    func randomSeedDeterminism() {
        randomSeed(42)
        let a1 = random(Float(100))
        let a2 = random(Float(100))
        randomSeed(42)
        let b1 = random(Float(100))
        let b2 = random(Float(100))
        #expect(a1 == b1)
        #expect(a2 == b2)
    }
}

// MARK: - Vec2 Tests

@Suite("Vec2 Extensions")
struct Vec2Tests {

    @Test("magnitude")
    func magnitudeTest() {
        let v = Vec2(3, 4)
        #expect(abs(v.magnitude - 5) < 0.0001)
    }

    @Test("magnitudeSquared")
    func magnitudeSquaredTest() {
        let v = Vec2(3, 4)
        #expect(abs(v.magnitudeSquared - 25) < 0.0001)
    }

    @Test("heading returns correct angle")
    func headingTest() {
        let v = Vec2(1, 0)
        #expect(abs(v.heading()) < 0.0001)
        let v2 = Vec2(0, 1)
        #expect(abs(v2.heading() - Float.pi / 2) < 0.0001)
    }

    @Test("rotated 90 degrees")
    func rotateTest() {
        let v = Vec2(1, 0)
        let r = v.rotated(Float.pi / 2)
        #expect(abs(r.x) < 0.0001)
        #expect(abs(r.y - 1) < 0.0001)
    }

    @Test("limited caps magnitude")
    func limitTest() {
        let v = Vec2(10, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 5) < 0.0001)
    }

    @Test("limited does not affect small vectors")
    func limitSmallTest() {
        let v = Vec2(2, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 2) < 0.0001)
    }

    @Test("normalized returns unit vector")
    func normalizedTest() {
        let v = Vec2(3, 4)
        let n = v.normalized()
        #expect(abs(n.magnitude - 1) < 0.0001)
    }

    @Test("normalized zero vector returns zero")
    func normalizedZeroTest() {
        let v = Vec2(0, 0)
        let n = v.normalized()
        #expect(n == .zero)
    }

    @Test("fromAngle creates correct vector")
    func fromAngleTest() {
        let v = Vec2.fromAngle(0)
        #expect(abs(v.x - 1) < 0.0001)
        #expect(abs(v.y) < 0.0001)
    }

    @Test("random2D has unit magnitude")
    func random2DTest() {
        for _ in 0..<20 {
            let v = Vec2.random2D()
            #expect(abs(v.magnitude - 1) < 0.001)
        }
    }

    @Test("dist to another vector")
    func distToTest() {
        let a = Vec2(0, 0)
        let b = Vec2(3, 4)
        #expect(abs(a.dist(to: b) - 5) < 0.0001)
    }

    @Test("dot product")
    func dotTest() {
        let a = Vec2(1, 0)
        let b = Vec2(0, 1)
        #expect(abs(a.dot(b)) < 0.0001)
    }

    @Test("lerp to another vector")
    func lerpTest() {
        let a = Vec2(0, 0)
        let b = Vec2(10, 10)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 5) < 0.0001)
    }
}

// MARK: - Vec3 Tests

@Suite("Vec3 Extensions")
struct Vec3Tests {

    @Test("magnitude")
    func magnitudeTest() {
        let v = Vec3(1, 2, 2)
        #expect(abs(v.magnitude - 3) < 0.0001)
    }

    @Test("limited caps magnitude")
    func limitTest() {
        let v = Vec3(10, 0, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 5) < 0.0001)
    }

    @Test("normalized returns unit vector")
    func normalizedTest() {
        let v = Vec3(1, 2, 2)
        let n = v.normalized()
        #expect(abs(n.magnitude - 1) < 0.0001)
    }

    @Test("random3D has unit magnitude")
    func random3DTest() {
        for _ in 0..<20 {
            let v = Vec3.random3D()
            #expect(abs(v.magnitude - 1) < 0.01)
        }
    }

    @Test("cross product correctness")
    func crossTest() {
        let x = Vec3(1, 0, 0)
        let y = Vec3(0, 1, 0)
        let z = x.cross(y)
        #expect(abs(z.x) < 0.0001)
        #expect(abs(z.y) < 0.0001)
        #expect(abs(z.z - 1) < 0.0001)
    }

    @Test("dist to another vector")
    func distToTest() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(1, 2, 2)
        #expect(abs(a.dist(to: b) - 3) < 0.0001)
    }

    @Test("lerp to another vector")
    func lerpTest() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(10, 20, 30)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 10) < 0.0001)
        #expect(abs(mid.z - 15) < 0.0001)
    }
}

// MARK: - SIMD2 lerp Tests

@Suite("SIMD2 lerp")
struct SIMD2LerpTests {

    @Test("lerp SIMD2 at boundaries")
    func lerpBoundaries() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(10, 20)
        let start = lerp(a, b, 0)
        let end = lerp(a, b, 1)
        let mid = lerp(a, b, 0.5)
        #expect(start == a)
        #expect(end == b)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 10) < 0.0001)
    }
}

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

// MARK: - InputManager Tests

@Suite("InputManager")
@MainActor
struct InputManagerTests {

    @Test("initial state is zero")
    func initialState() {
        let input = InputManager()
        #expect(input.mouseX == 0)
        #expect(input.mouseY == 0)
        #expect(input.isMouseDown == false)
        #expect(input.isKeyPressed == false)
    }

    @Test("mouse down updates state")
    func mouseDown() {
        let input = InputManager()
        input.handleMouseDown(x: 100, y: 200, button: 0)
        #expect(input.mouseX == 100)
        #expect(input.mouseY == 200)
        #expect(input.isMouseDown == true)
        #expect(input.mouseButton == 0)
    }

    @Test("mouse up clears isMouseDown")
    func mouseUp() {
        let input = InputManager()
        input.handleMouseDown(x: 100, y: 200, button: 0)
        input.handleMouseUp(x: 100, y: 200, button: 0)
        #expect(input.isMouseDown == false)
    }

    @Test("mouse moved updates position")
    func mouseMoved() {
        let input = InputManager()
        input.handleMouseMoved(x: 50, y: 75)
        #expect(input.mouseX == 50)
        #expect(input.mouseY == 75)
    }

    @Test("frame update saves previous position")
    func frameUpdate() {
        let input = InputManager()
        input.handleMouseMoved(x: 10, y: 20)
        input.updateFrame()
        input.handleMouseMoved(x: 30, y: 40)
        #expect(input.pmouseX == 10)
        #expect(input.pmouseY == 20)
        #expect(input.mouseX == 30)
        #expect(input.mouseY == 40)
    }

    @Test("key down/up tracking")
    func keyTracking() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 49, characters: " ")
        #expect(input.isKeyPressed == true)
        #expect(input.isKeyDown(49) == true)
        #expect(input.lastKeyCode == 49)
        #expect(input.lastKey == " ")

        input.handleKeyUp(keyCode: 49)
        #expect(input.isKeyPressed == false)
        #expect(input.isKeyDown(49) == false)
    }

    @Test("multiple keys tracked independently")
    func multipleKeys() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 0, characters: "a")
        input.handleKeyDown(keyCode: 1, characters: "s")
        #expect(input.isKeyDown(0) == true)
        #expect(input.isKeyDown(1) == true)

        input.handleKeyUp(keyCode: 0)
        #expect(input.isKeyDown(0) == false)
        #expect(input.isKeyDown(1) == true)
        #expect(input.isKeyPressed == true)
    }

    @Test("callbacks are invoked")
    func callbacks() {
        let input = InputManager()
        var called = false
        input.onMousePressed = { _, _, _ in called = true }
        input.handleMouseDown(x: 0, y: 0, button: 0)
        #expect(called == true)
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
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        #expect(canvas.width == 1920)
        #expect(canvas.height == 1080)
    }
}

// MARK: - MetaphorRenderer Input Integration Tests

@Suite("MetaphorRenderer Input", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct RendererInputTests {

    @Test("renderer has input manager")
    func rendererHasInput() {
        let renderer = MetaphorRenderer()!
        #expect(renderer.input.mouseX == 0)
        #expect(renderer.input.isMouseDown == false)
    }
}

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
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.width == 1920)
        #expect(context.height == 1080)
    }

    @Test("context initial state")
    func initialState() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.time == 0)
        #expect(context.deltaTime == 0)
        #expect(context.frameCount == 0)
    }

    @Test("context exposes renderer")
    func escapteHatch() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.renderer === renderer)
        #expect(context.canvas === canvas)
        #expect(context.input === renderer.input)
    }

    @Test("context encoder is nil outside frame")
    func encoderOutsideFrame() throws {
        let renderer = MetaphorRenderer()!
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(context.encoder == nil)
    }
}

// MARK: - Canvas2D currentEncoder Tests

@Suite("Canvas2D Encoder Access", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DEncoderTests {

    @Test("currentEncoder is nil before begin")
    func encoderNilBeforeBegin() throws {
        let renderer = MetaphorRenderer()!
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

// MARK: - Mesh Tests

@Suite("Mesh", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MeshTests {

    @Test("box has 24 vertices and 36 indices")
    func boxCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.box(device: device)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.indexCount == 36)
        #expect(mesh.indexBuffer != nil)
    }

    @Test("sphere has expected vertex count")
    func sphereCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.sphere(device: device, radius: 1, segments: 8, rings: 4)
        // (rings+1) * (segments+1) = 5 * 9 = 45
        #expect(mesh.vertexCount == 45)
        // rings * segments * 6 = 4 * 8 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("plane has 4 vertices and 6 indices")
    func planeCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.plane(device: device)
        #expect(mesh.vertexCount == 4)
        #expect(mesh.indexCount == 6)
    }

    @Test("cylinder has expected index count")
    func cylinderCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cylinder(device: device, segments: 8)
        // Side: 8*6=48, Top cap: 8*3=24, Bot cap: 8*3=24 = 96
        #expect(mesh.indexCount == 96)
    }

    @Test("cone has expected index count")
    func coneCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cone(device: device, segments: 8)
        // Side: 8*3=24, Bot cap: 8*3=24 = 48
        #expect(mesh.indexCount == 48)
    }

    @Test("torus has expected vertex count")
    func torusCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.torus(device: device, segments: 8, tubeSegments: 4)
        // (segments+1) * (tubeSegments+1) = 9 * 5 = 45
        #expect(mesh.vertexCount == 45)
        // segments * tubeSegments * 6 = 8 * 4 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("box with custom dimensions")
    func boxCustom() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.box(device: device, width: 2, height: 3, depth: 4)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.indexCount == 36)
    }
}

// MARK: - Canvas3D Tests

@Suite("Canvas3D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DTests {

    @Test("can create Canvas3D from renderer")
    func createFromRenderer() throws {
        let renderer = MetaphorRenderer()!
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

// MARK: - Easing Tests

@Suite("Easing")
struct EasingTests {

    @Test("polynomial easings have correct boundaries")
    func polynomialBoundaries() {
        let fns: [(Float) -> Float] = [
            easeInQuad, easeOutQuad, easeInOutQuad,
            easeInCubic, easeOutCubic, easeInOutCubic,
            easeInQuart, easeOutQuart, easeInOutQuart,
            easeInQuint, easeOutQuint, easeInOutQuint,
        ]
        for f in fns {
            #expect(abs(f(0) - 0) < 0.0001, "f(0) should be 0")
            #expect(abs(f(1) - 1) < 0.0001, "f(1) should be 1")
        }
    }

    @Test("trigonometric easings have correct boundaries")
    func trigBoundaries() {
        let fns: [(Float) -> Float] = [
            easeInSine, easeOutSine, easeInOutSine,
            easeInCirc, easeOutCirc, easeInOutCirc,
        ]
        for f in fns {
            #expect(abs(f(0) - 0) < 0.0001, "f(0) should be 0")
            #expect(abs(f(1) - 1) < 0.0001, "f(1) should be 1")
        }
    }

    @Test("expo easings have correct boundaries")
    func expoBoundaries() {
        #expect(easeInExpo(0) == 0)
        #expect(abs(easeInExpo(1) - 1) < 0.01)
        #expect(abs(easeOutExpo(0)) < 0.0001)
        #expect(easeOutExpo(1) == 1)
        #expect(easeInOutExpo(0) == 0)
        #expect(easeInOutExpo(1) == 1)
    }

    @Test("back easings have correct boundaries")
    func backBoundaries() {
        #expect(abs(easeInBack(0)) < 0.0001)
        #expect(abs(easeInBack(1) - 1) < 0.0001)
        #expect(abs(easeOutBack(0)) < 0.0001)
        #expect(abs(easeOutBack(1) - 1) < 0.0001)
        #expect(abs(easeInOutBack(0)) < 0.0001)
        #expect(abs(easeInOutBack(1) - 1) < 0.0001)
    }

    @Test("elastic easings have correct boundaries")
    func elasticBoundaries() {
        #expect(easeInElastic(0) == 0)
        #expect(easeInElastic(1) == 1)
        #expect(easeOutElastic(0) == 0)
        #expect(easeOutElastic(1) == 1)
        #expect(easeInOutElastic(0) == 0)
        #expect(easeInOutElastic(1) == 1)
    }

    @Test("bounce easings have correct boundaries")
    func bounceBoundaries() {
        #expect(abs(easeInBounce(0)) < 0.0001)
        #expect(abs(easeInBounce(1) - 1) < 0.0001)
        #expect(abs(easeOutBounce(0)) < 0.0001)
        #expect(abs(easeOutBounce(1) - 1) < 0.0001)
        #expect(abs(easeInOutBounce(0)) < 0.0001)
        #expect(abs(easeInOutBounce(1) - 1) < 0.0001)
    }

    @Test("easeInOut midpoint is approximately 0.5")
    func midpoint() {
        let fns: [(Float) -> Float] = [
            easeInOutQuad, easeInOutCubic, easeInOutQuart, easeInOutQuint,
            easeInOutSine, easeInOutExpo, easeInOutCirc,
        ]
        for f in fns {
            #expect(abs(f(0.5) - 0.5) < 0.01, "easeInOut(0.5) should be ~0.5")
        }
    }

    @Test("easeIn is slower than linear at midpoint")
    func easeInSlower() {
        #expect(easeInQuad(0.5) < 0.5)
        #expect(easeInCubic(0.5) < 0.5)
        #expect(easeInQuart(0.5) < 0.5)
    }

    @Test("easeOut is faster than linear at midpoint")
    func easeOutFaster() {
        #expect(easeOutQuad(0.5) > 0.5)
        #expect(easeOutCubic(0.5) > 0.5)
        #expect(easeOutQuart(0.5) > 0.5)
    }

    @Test("ease convenience interpolates correctly")
    func easeConvenience() {
        let result = ease(0.5, from: 10, to: 20, using: easeInOutQuad)
        #expect(abs(result - 15) < 0.01)
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

// MARK: - MImage Tests

@Suite("MImage", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MImageTests {

    @Test("MImage from texture")
    func fromTexture() {
        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 64, height: 32, mipmapped: false
        )
        desc.usage = .shaderRead
        let texture = device.makeTexture(descriptor: desc)!
        let img = MImage(texture: texture)
        #expect(img.width == 64)
        #expect(img.height == 32)
    }
}

// MARK: - TextRenderer Tests

@Suite("TextRenderer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct TextRendererTests {

    @Test("can render text to texture")
    func renderText() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let cached = renderer.textTexture(
            string: "Hello",
            fontSize: 32,
            fontFamily: "Helvetica",
            frameCount: 1
        )
        #expect(cached != nil)
        #expect(cached!.width > 0)
        #expect(cached!.height > 0)
    }

    @Test("cache hit returns same texture")
    func cacheHit() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let first = renderer.textTexture(
            string: "Test", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        let second = renderer.textTexture(
            string: "Test", fontSize: 24, fontFamily: "Helvetica", frameCount: 2
        )
        #expect(first != nil)
        #expect(second != nil)
        #expect(first!.texture === second!.texture)
    }

    @Test("different params produce different textures")
    func cacheMiss() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let a = renderer.textTexture(
            string: "AAA", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        let b = renderer.textTexture(
            string: "BBB", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        #expect(a != nil)
        #expect(b != nil)
        #expect(a!.texture !== b!.texture)
    }
}

// MARK: - Screenshot Tests

@Suite("Screenshot", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ScreenshotTests {

    @Test("renderer has saveScreenshot method")
    func saveScreenshotAPI() {
        let renderer = MetaphorRenderer()!
        // pendingSavePath が設定されることを確認（直接アクセスはできないがクラッシュしないことを検証）
        renderer.saveScreenshot(to: "/tmp/test_screenshot.png")
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

// MARK: - ComputeKernel Tests

@Suite("ComputeKernel", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ComputeKernelTests {

    @Test("can create kernel from MSL source")
    func createFromSource() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void testKernel(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = float(id);
        }
        """
        let kernel = try ComputeKernel(device: device, source: source, functionName: "testKernel")
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
        #expect(kernel.threadExecutionWidth > 0)
    }

    @Test("throws on invalid function name")
    func invalidFunction() {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void realFunction(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 0;
        }
        """
        #expect(throws: ComputeKernelError.self) {
            try ComputeKernel(device: device, source: source, functionName: "nonExistent")
        }
    }

    @Test("can create kernel from MTLFunction")
    func createFromFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void testFn(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 1.0;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let function = library.makeFunction(name: "testFn")!
        let kernel = try ComputeKernel(device: device, function: function)
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
    }
}

// MARK: - GPUBuffer Tests

@Suite("GPUBuffer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct GPUBufferTests {

    @Test("can create empty buffer")
    func createEmpty() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 100)
        #expect(buf != nil)
        #expect(buf!.count == 100)
        #expect(buf![0] == 0)
    }

    @Test("can create buffer from array")
    func createFromArray() {
        let device = MTLCreateSystemDefaultDevice()!
        let data: [Float] = [1.0, 2.0, 3.0, 4.0]
        let buf = GPUBuffer<Float>(device: device, data: data)
        #expect(buf != nil)
        #expect(buf!.count == 4)
        #expect(buf![0] == 1.0)
        #expect(buf![3] == 4.0)
    }

    @Test("subscript get/set")
    func subscriptAccess() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 10)!
        buf[5] = 42.0
        #expect(buf[5] == 42.0)
    }

    @Test("toArray returns copy")
    func toArray() {
        let device = MTLCreateSystemDefaultDevice()!
        let data: [SIMD2<Float>] = [SIMD2(1, 2), SIMD2(3, 4)]
        let buf = GPUBuffer<SIMD2<Float>>(device: device, data: data)!
        let arr = buf.toArray()
        #expect(arr.count == 2)
        #expect(arr[0] == SIMD2(1, 2))
    }

    @Test("copyFrom copies data")
    func copyFrom() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Int32>(device: device, count: 4)!
        buf.copyFrom([10, 20, 30, 40])
        #expect(buf[0] == 10)
        #expect(buf[3] == 40)
    }

    @Test("works with custom struct")
    func customStruct() {
        struct Particle {
            var x: Float
            var y: Float
            var vx: Float
            var vy: Float
        }
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Particle>(device: device, count: 100)!
        buf[0] = Particle(x: 1, y: 2, vx: 3, vy: 4)
        #expect(buf[0].x == 1)
        #expect(buf[0].vy == 4)
    }

    @Test("buffer has correct byte length")
    func byteLength() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 256)!
        #expect(buf.buffer.length == MemoryLayout<Float>.stride * 256)
    }
}

// MARK: - Compute Integration Tests

@Suite("Compute Integration", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ComputeIntegrationTests {

    @Test("can dispatch compute kernel and read results")
    func dispatchAndRead() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void fillBuffer(device float *output [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            output[id] = float(id) * 2.0;
        }
        """
        let kernel = try ComputeKernel(device: device, source: source, functionName: "fillBuffer")
        let buffer = GPUBuffer<Float>(device: device, count: 64)!

        let commandQueue = device.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(kernel.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)

        let w = kernel.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: 64, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(buffer[0] == 0.0)
        #expect(buffer[1] == 2.0)
        #expect(buffer[63] == 126.0)
    }

    @Test("double dispatch with barrier reads correct data")
    func doubleDispatchWithBarrier() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void step1(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = float(id);
        }
        kernel void step2(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = buf[id] * 3.0;
        }
        """
        let kernel1 = try ComputeKernel(device: device, source: source, functionName: "step1")
        let kernel2 = try ComputeKernel(device: device, source: source, functionName: "step2")
        let buffer = GPUBuffer<Float>(device: device, count: 32)!

        let commandQueue = device.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(kernel1.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        let w = kernel1.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: 32, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )

        encoder.memoryBarrier(scope: .buffers)

        encoder.setComputePipelineState(kernel2.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: 32, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(buffer[0] == 0.0)
        #expect(buffer[1] == 3.0)
        #expect(buffer[10] == 30.0)
    }
}

// MARK: - SketchContext Compute Tests

@Suite("SketchContext Compute", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextComputeTests {

    @Test("createComputeKernel compiles MSL source")
    func createKernel() throws {
        let renderer = MetaphorRenderer()!
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
        let renderer = MetaphorRenderer()!
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
        let renderer = MetaphorRenderer()!
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
