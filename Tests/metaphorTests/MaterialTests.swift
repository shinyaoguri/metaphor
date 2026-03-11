import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - CustomMaterial Property Tests

@Suite("CustomMaterial Properties")
@MainActor
struct CustomMaterialPropertyTests {

    @Test("CustomMaterial stores fragment function name")
    func fragmentFunctionName() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        // カスタムフラグメントシェーダーソース
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        fragment float4 testCustomFragment(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return in.color;
        }
        """

        let key = "test.material.testCustomFragment"
        try library.register(source: source, as: key)
        let fn = library.function(named: "testCustomFragment", from: key)!

        let mat = CustomMaterial(fragmentFunction: fn, functionName: "testCustomFragment", libraryKey: key)
        #expect(mat.fragmentFunctionName == "testCustomFragment")
        #expect(mat.libraryKey == key)
    }

    @Test("setParameters stores Float bytes correctly")
    func setParametersFloat() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        fragment float4 testParamFragment(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]],
            constant float &customParam [[buffer(4)]]
        ) {
            return float4(customParam, 0, 0, 1);
        }
        """

        let key = "test.material.testParamFragment"
        try library.register(source: source, as: key)
        let fn = library.function(named: "testParamFragment", from: key)!

        let mat = CustomMaterial(fragmentFunction: fn, functionName: "testParamFragment", libraryKey: key)

        #expect(mat.parameters == nil)

        mat.setParameters(Float(42.0))
        #expect(mat.parameters != nil)
        #expect(mat.parameters!.count == MemoryLayout<Float>.size)
    }

    @Test("setParameters stores struct bytes correctly")
    func setParametersStruct() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        struct CustomParams {
            float4 tintColor;
            float intensity;
        };

        fragment float4 testStructParamFragment(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]],
            constant CustomParams &params [[buffer(4)]]
        ) {
            return in.color * params.tintColor * params.intensity;
        }
        """

        let key = "test.material.testStructParamFragment"
        try library.register(source: source, as: key)
        let fn = library.function(named: "testStructParamFragment", from: key)!

        let mat = CustomMaterial(fragmentFunction: fn, functionName: "testStructParamFragment", libraryKey: key)

        struct CustomParams {
            var tintColor: SIMD4<Float>
            var intensity: Float
        }

        let params = CustomParams(tintColor: SIMD4(1, 0, 0, 1), intensity: 0.5)
        mat.setParameters(params)

        #expect(mat.parameters != nil)
        #expect(mat.parameters!.count == MemoryLayout<CustomParams>.size)
    }
}

// MARK: - CustomMaterial Pipeline Tests

@Suite("CustomMaterial Pipeline", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CustomMaterialPipelineTests {

    @Test("custom material pipeline can be built for untextured mesh")
    func untexturedPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        fragment float4 testUntexturedCustom(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return float4(in.normal * 0.5 + 0.5, 1.0);
        }
        """

        let key = "test.material.testUntexturedCustom"
        try library.register(source: source, as: key)
        let fragFn = library.function(named: "testUntexturedCustom", from: key)!

        let vertFn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )

        // パイプラインが例外なくビルドできることを確認
        _ = try PipelineFactory(device: device)
            .vertex(vertFn)
            .fragment(fragFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .build()
    }

    @Test("custom material pipeline can be built for textured mesh")
    func texturedPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DTexVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float2 uv;
        };

        fragment float4 testTexturedCustom(
            Canvas3DTexVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]],
            texture2d<float> tex [[texture(0)]]
        ) {
            constexpr sampler s(filter::linear);
            float4 texColor = tex.sample(s, in.uv);
            return texColor;
        }
        """

        let key = "test.material.testTexturedCustom"
        try library.register(source: source, as: key)
        let fragFn = library.function(named: "testTexturedCustom", from: key)!

        let vertFn = library.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )

        // パイプラインが例外なくビルドできることを確認
        _ = try PipelineFactory(device: device)
            .vertex(vertFn)
            .fragment(fragFn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .build()
    }
}

// MARK: - Canvas3D Custom Material State Tests

@Suite("Canvas3D CustomMaterial State", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DCustomMaterialStateTests {

    @Test("canvas3DStructs is publicly accessible")
    func canvas3DStructsPublic() {
        let structs = BuiltinShaders.canvas3DStructs
        #expect(structs.contains("Canvas3DUniforms"))
        #expect(structs.contains("Light3D"))
        #expect(structs.contains("Material3D"))
    }

    @Test("canvas3DLightingFn is publicly accessible")
    func canvas3DLightingFnPublic() {
        let lightingFn = BuiltinShaders.canvas3DLightingFn
        #expect(lightingFn.contains("calculateLighting"))
    }

    @Test("Canvas3D noMaterial and material methods exist")
    func materialMethodsExist() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)
        let canvas3D = try Canvas3D(
            device: device,
            shaderLibrary: library,
            depthStencilCache: depthCache,
            width: 100,
            height: 100
        )

        // noMaterial should be callable without error
        canvas3D.noMaterial()

        // Create a custom material and set it
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        fragment float4 testStateMaterial(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return in.color;
        }
        """

        let key = "test.material.testStateMaterial"
        try library.register(source: source, as: key)
        let fn = library.function(named: "testStateMaterial", from: key)!
        let mat = CustomMaterial(fragmentFunction: fn, functionName: "testStateMaterial", libraryKey: key)

        // material() should be callable
        canvas3D.material(mat)

        // noMaterial() should reset
        canvas3D.noMaterial()
    }
}

// MARK: - MetaphorError.material Tests

@Suite("MetaphorError.material")
struct CustomMaterialErrorTests {

    @Test("shaderNotFound error contains function name")
    func shaderNotFoundError() {
        let error = MetaphorError.material(.shaderNotFound("nonExistentFunction"))
        if case .material(.shaderNotFound(let name)) = error {
            #expect(name == "nonExistentFunction")
        } else {
            Issue.record("Expected material shaderNotFound error")
        }
    }
}
