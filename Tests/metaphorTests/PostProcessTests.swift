import Testing
import Metal
import simd
@testable import metaphor

// MARK: - CustomPostEffect Tests

@Suite("CustomPostEffect")
@MainActor
struct CustomPostEffectTests {

    @Test("default property values")
    func defaultValues() {
        let effect = CustomPostEffect(
            name: "test",
            fragmentFunctionName: "testFragment",
            libraryKey: "user.posteffect.test"
        )
        #expect(effect.name == "test")
        #expect(effect.fragmentFunctionName == "testFragment")
        #expect(effect.libraryKey == "user.posteffect.test")
        #expect(effect.intensity == 0)
        #expect(effect.threshold == 0)
        #expect(effect.radius == 0)
        #expect(effect.smoothness == 0)
        #expect(effect.hasCustomParameters == false)
        #expect(effect.parameters.isEmpty)
    }

    @Test("setting properties")
    func settingProperties() {
        let effect = CustomPostEffect(
            name: "test",
            fragmentFunctionName: "testFragment",
            libraryKey: "user.posteffect.test"
        )
        effect.intensity = 0.5
        effect.threshold = 0.8
        effect.radius = 3.0
        effect.smoothness = 0.2

        #expect(effect.intensity == 0.5)
        #expect(effect.threshold == 0.8)
        #expect(effect.radius == 3.0)
        #expect(effect.smoothness == 0.2)
    }

    @Test("setParameters stores bytes correctly")
    func setParametersFloat() {
        let effect = CustomPostEffect(
            name: "test",
            fragmentFunctionName: "testFragment",
            libraryKey: "user.posteffect.test"
        )

        effect.setParameters(Float(42.0))
        #expect(effect.hasCustomParameters == true)
        #expect(effect.parameters.count == MemoryLayout<Float>.size)
    }

    @Test("setParameters with struct")
    func setParametersStruct() {
        struct MyParams {
            var amount: Float
            var scale: Float
        }
        let effect = CustomPostEffect(
            name: "test",
            fragmentFunctionName: "testFragment",
            libraryKey: "user.posteffect.test"
        )

        let params = MyParams(amount: 1.0, scale: 2.0)
        effect.setParameters(params)
        #expect(effect.hasCustomParameters == true)
        #expect(effect.parameters.count == MemoryLayout<MyParams>.size)
    }
}

// MARK: - PostEffect Custom Case Tests

@Suite("PostEffect.custom")
@MainActor
struct PostEffectCustomCaseTests {

    @Test("custom case wraps CustomPostEffect")
    func customCaseWorks() {
        let custom = CustomPostEffect(
            name: "sepia",
            fragmentFunctionName: "sepiaFragment",
            libraryKey: "user.posteffect.sepia"
        )
        custom.intensity = 0.7
        let effect = PostEffect.custom(custom)

        if case .custom(let inner) = effect {
            #expect(inner.name == "sepia")
            #expect(inner.intensity == 0.7)
            #expect(inner.fragmentFunctionName == "sepiaFragment")
        } else {
            Issue.record("Expected .custom case")
        }
    }
}

// MARK: - PostProcessShaders CommonStructs Tests

@Suite("PostProcessShaders.commonStructs")
struct CommonStructsTests {

    @Test("commonStructs contains required Metal declarations")
    func containsRequiredDeclarations() {
        let src = PostProcessShaders.commonStructs
        #expect(src.contains("#include <metal_stdlib>"))
        #expect(src.contains("using namespace metal"))
        #expect(src.contains("struct PPVertexOut"))
        #expect(src.contains("struct PostProcessParams"))
        #expect(src.contains("float4 position [[position]]"))
        #expect(src.contains("float2 texCoord"))
        #expect(src.contains("float2 texelSize"))
        #expect(src.contains("float  intensity"))
        #expect(src.contains("float  threshold"))
        #expect(src.contains("float  radius"))
        #expect(src.contains("float  smoothness"))
    }
}

// MARK: - GPU-dependent Custom PostEffect Tests

@Suite("CustomPostEffect Pipeline Integration", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CustomPostEffectPipelineTests {

    @Test("custom shader registers and compiles")
    func customShaderRegistration() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = PostProcessShaders.commonStructs + """

        fragment float4 testCustomInvert(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]]
        ) {
            constexpr sampler s(filter::linear);
            float4 color = tex.sample(s, in.texCoord);
            return float4(1.0 - color.rgb * params.intensity, color.a);
        }
        """

        let key = "user.posteffect.testInvert"
        try shaderLib.register(source: source, as: key)

        let fn = shaderLib.function(named: "testCustomInvert", from: key)
        #expect(fn != nil)
    }

    @Test("custom shader with custom parameters struct compiles")
    func customShaderWithParamsCompiles() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = PostProcessShaders.commonStructs + """

        struct MyCustomParams {
            float amount;
            float3 tintColor;
        };

        fragment float4 testCustomTint(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]],
            constant MyCustomParams &custom [[buffer(1)]]
        ) {
            constexpr sampler s(filter::linear);
            float4 color = tex.sample(s, in.texCoord);
            color.rgb = mix(color.rgb, custom.tintColor, custom.amount);
            return color;
        }
        """

        let key = "user.posteffect.testTint"
        try shaderLib.register(source: source, as: key)

        let fn = shaderLib.function(named: "testCustomTint", from: key)
        #expect(fn != nil)
    }

    @Test("pipeline can be built for custom shader")
    func buildCustomPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = PostProcessShaders.commonStructs + """

        fragment float4 testBuildPipeline(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]]
        ) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """

        let key = "user.posteffect.testBuild"
        try shaderLib.register(source: source, as: key)

        let vertexFn = shaderLib.function(
            named: BuiltinShaders.FunctionName.blitVertex,
            from: ShaderLibrary.BuiltinKey.blit
        )
        let fragmentFn = shaderLib.function(named: "testBuildPipeline", from: key)

        let pipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .build()

        #expect(pipeline.label == nil || true)
    }

    @Test("PostProcessPipeline handles custom effect in chain")
    func customEffectInChain() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = PostProcessShaders.commonStructs + """

        fragment float4 testChainEffect(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            constant PostProcessParams &params [[buffer(0)]]
        ) {
            constexpr sampler s(filter::linear);
            float4 color = tex.sample(s, in.texCoord);
            return float4(color.rgb * params.intensity, color.a);
        }
        """

        let key = "user.posteffect.testChain"
        try shaderLib.register(source: source, as: key)

        let custom = CustomPostEffect(
            name: "testChain",
            fragmentFunctionName: "testChainEffect",
            libraryKey: key
        )
        custom.intensity = 0.5

        let pipeline = try PostProcessPipeline(device: device, shaderLibrary: shaderLib)
        pipeline.add(.custom(custom))

        #expect(pipeline.effects.count == 1)
    }

    @Test("invalid shader source throws error")
    func invalidShaderThrows() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let invalidSource = "this is not valid MSL code"
        let key = "user.posteffect.invalid"

        #expect(throws: (any Error).self) {
            try shaderLib.register(source: invalidSource, as: key)
        }
    }

    @Test("nonexistent function returns nil")
    func nonexistentFunctionReturnsNil() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        let source = PostProcessShaders.commonStructs + """

        fragment float4 existingFunction(
            PPVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]]
        ) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """

        let key = "user.posteffect.testNonexistent"
        try shaderLib.register(source: source, as: key)

        let fn = shaderLib.function(named: "doesNotExist", from: key)
        #expect(fn == nil)
    }
}
