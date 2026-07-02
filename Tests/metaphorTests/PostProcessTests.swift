import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorMPS

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

// MARK: - PostEffect Protocol Conformance Tests

@Suite("PostEffect Protocol")
@MainActor
struct PostEffectProtocolTests {

    @Test("CustomPostEffect conforms to PostEffect protocol")
    func customConformsToProtocol() {
        let custom = CustomPostEffect(
            name: "sepia",
            fragmentFunctionName: "sepiaFragment",
            libraryKey: "user.posteffect.sepia"
        )
        custom.intensity = 0.7
        let effect: any PostEffect = custom
        #expect(effect.name == "sepia")
    }

    @Test("Built-in effects conform to PostEffect protocol")
    func builtinEffects() {
        let effects: [any PostEffect] = [
            BloomEffect(),
            BlurEffect(),
            InvertEffect(),
            GrayscaleEffect(),
            VignetteEffect(),
            ChromaticAberrationEffect(),
            ColorGradeEffect(),
            MPSBlurEffect(sigma: 3.0),
            MPSSobelEffect(),
            MPSErodeEffect(),
            MPSDilateEffect(),
        ]
        #expect(effects.count == 11)
        #expect(effects[0].name == "bloom")
        #expect(effects[2].name == "invert")
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

        // build() が throw せず非オプショナルの pipeline を返せること自体が成功条件。
        _ = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .noDepth()
            .build()
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

        let queue = device.makeCommandQueue()!
        let pipeline = try PostProcessPipeline(device: device, commandQueue: queue, shaderLibrary: shaderLib)
        pipeline.add(custom)

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

// MARK: - PostFX リソース再利用（#159）

@Suite("PostFX Resource Reuse", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PostFXResourceReuseTests {

    @Test("filter output textures are recycled through the pool")
    func texturePoolRecycling() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let image = try #require(MImage.createImage(64, 64, device: renderer.device))
        let gpu = renderer.imageFilterGPU

        // 1 回目: プールから新規確保（旧テクスチャは shared のため返却対象外）
        gpu.apply(.invert, to: image)
        let t1 = image.texture
        // 2 回目: 新規確保、t1（private・プール由来）が返却される
        gpu.apply(.invert, to: image)
        let t2 = image.texture
        // 3 回目: 返却済みの t1 が再利用される（旧実装は毎回新規確保）
        gpu.apply(.invert, to: image)
        let t3 = image.texture

        #expect(t2 !== t1)
        #expect(t3 === t1, "3 回目の出力はプールへ返却された 1 回目の出力テクスチャを再利用する")
    }

    @Test("MPS gaussian kernel cache stays bounded under sigma animation")
    func mpsKernelCacheBounded() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let image = try #require(MImage.createImage(32, 32, device: renderer.device))
        let gpu = renderer.imageFilterGPU

        for i in 0..<40 {
            gpu.apply(.mpsBlur(sigma: 1.0 + Float(i) * 0.1), to: image)
        }
        // 上限 16 超過で全クリアされるため、17 を超えて増殖しない
        #expect(gpu._gaussianCacheCountForTesting <= 17)
    }

    @Test("kawase chain is reused across different iteration counts")
    func kawaseChainReuse() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let pipeline = try PostProcessPipeline(
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary
        )
        let ctx = pipeline.context

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let src = try #require(renderer.device.makeTexture(descriptor: desc))
        let dst = try #require(renderer.device.makeTexture(descriptor: desc))
        let cb = try #require(renderer.commandQueue.makeCommandBuffer())

        // Blur(6) → Bloom(4) の併用パターン: チェーンは縮まず同一テクスチャを再利用
        ctx.applyKawaseBlur(commandBuffer: cb, source: src, output: dst, iterations: 6)
        let chain6 = ctx._kawaseChainForTesting
        #expect(chain6.count == 6)

        ctx.applyKawaseBlur(commandBuffer: cb, source: src, output: dst, iterations: 4)
        let chainAfter = ctx._kawaseChainForTesting
        #expect(chainAfter.count == 6, "少ない iterations の要求でチェーンを破棄しない")
        for (a, b) in zip(chain6, chainAfter) {
            #expect(a === b, "既存レベルのテクスチャが再利用される")
        }

        // 再び 6 を要求しても再確保されない
        ctx.applyKawaseBlur(commandBuffer: cb, source: src, output: dst, iterations: 6)
        for (a, b) in zip(chain6, ctx._kawaseChainForTesting) {
            #expect(a === b)
        }
        cb.commit()
    }
}
