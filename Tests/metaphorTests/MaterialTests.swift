import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - CustomMaterial Property Tests

@Suite("CustomMaterial Properties", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
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

// MARK: - 前文の自動付与 (#713)

/// `createMaterial()` / `createMaterialFromFile()` が前文を**必ず**足すことを固定する。
///
/// 2D（`createShader` / `loadShader`）は前からそうなっていたが、3D はユーザーが手で
/// 前置する作法だった。忘れると `use of undeclared identifier 'Canvas3DUniforms'` で
/// 落ちる一方、以前の作法で自分で前置しているソースも動き続ける必要がある（前文が
/// `#ifndef` ガードを持つのはそのため）。両方をここで見る。
@Suite("CustomMaterial Preamble", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CustomMaterialPreambleTests {

    /// 前文を 1 行も書かない、フラグメント関数だけのソース。
    private static let bareSource = """
    fragment float4 bareFragment(
        Canvas3DVertexOut in [[stage_in]],
        constant Canvas3DUniforms &uniforms [[buffer(1)]],
        constant Light3D *lights [[buffer(2)]],
        constant Material3D &material [[buffer(3)]]
    ) {
        float3 lit = calculateLighting(
            in.worldPosition, in.normal, uniforms.cameraPosition.xyz,
            in.color.rgb, lights, uniforms.lightCount, material);
        return float4(lit, in.color.a);
    }
    """

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    @Test("前文を書かないフラグメント関数だけのソースが通る")
    func bareFragmentCompiles() throws {
        let context = try makeContext()
        let material = try context.createMaterial(
            source: Self.bareSource, fragmentFunction: "bareFragment")
        #expect(material.fragmentFunctionName == "bareFragment")
    }

    @Test("自分で前文を前置した従来形のソースも通る")
    func selfPrefixedSourceStillCompiles() throws {
        // #713 以前に案内していた書き方。ガードが効いていないと、前文が 2 回現れて
        // `redefinition of 'Canvas3DUniforms'` で落ちる。
        let legacy = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)
        \(BuiltinShaders.canvas3DLightingFn)

        \(Self.bareSource)
        """
        let context = try makeContext()
        let material = try context.createMaterial(
            source: legacy, fragmentFunction: "bareFragment")
        #expect(material.fragmentFunctionName == "bareFragment")
    }

    @Test("ファイルから読む経路でも前文が足される")
    func fileSourceGetsPreamble() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metaphor-preamble-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bare.metal")
        try Self.bareSource.write(to: file, atomically: true, encoding: .utf8)

        let context = try makeContext()
        let material = try context.createMaterialFromFile(
            path: file.path, fragmentFunction: "bareFragment")
        #expect(material.fragmentFunctionName == "bareFragment")
    }

    @Test("読めないパスは shaderSourceLoadFailed になる")
    func missingFileThrows() throws {
        let context = try makeContext()
        #expect(throws: MetaphorError.self) {
            _ = try context.createMaterialFromFile(
                path: "/nonexistent/metaphor-\(UUID().uuidString).metal",
                fragmentFunction: "bareFragment")
        }
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
