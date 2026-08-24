import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore

/// カスタムシェーダ用の前文（``BuiltinShaders/canvas2DStructs`` /
/// ``BuiltinShaders/canvas3DStructs`` / ``BuiltinShaders/canvas3DLightingFn`` /
/// ``PostProcessShaders/commonStructs``）を、実際に MSL としてコンパイルして固定する。
///
/// この前文は組み込みシェーダー（`Shaders/Metal/*.h`）と**同じ実装を配る**ものなので、
/// 片方だけ直すと組み込みとカスタムマテリアルで挙動が食い違う（#707）。従来の検査は
/// 「文字列に `calculateLighting` が含まれるか」止まりで、シグネチャが欠けても構造体の
/// レイアウトがずれても緑のままだった。ここでコンパイルまで通すことで、
///
/// - 前文だけで MSL が成立すること（型・関数の取りこぼしが無いこと）
/// - 公開しているライティング関数の**全シグネチャ**が解決すること
/// - 構造体のレイアウトが Swift 側（``Canvas3DUniforms`` 等）と一致すること
///
/// を保証する。
@Suite("Shader Prelude", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ShaderPreludeTests {

    /// 前文が持たない部分（ユーザーが自分で書く想定の 2 行）。
    private static let stdlib = """
        #include <metal_stdlib>
        using namespace metal;
        """

    private func compile(_ source: String) throws -> MTLLibrary {
        let device = MTLCreateSystemDefaultDevice()!
        return try device.makeLibrary(source: source, options: nil)
    }

    // MARK: - 構造体

    @Test("canvas3DStructs だけで 4 つの構造体が揃い、Swift 側とレイアウトが一致する")
    func structsCompileAndMatchSwiftLayout() throws {
        // `static_assert` は MSL（C++14 ベース）で使える。Swift 側の stride を
        // そのまま埋め込むので、どちらかのフィールドが増減した時点でコンパイルが落ちる。
        let source = """
            \(Self.stdlib)

            \(BuiltinShaders.canvas3DStructs)

            // メッセージを英語にしているのは、Metal のコンパイルエラーが非 ASCII を
            // 8 進エスケープで吐き、日本語だと読めなくなるため。
            static_assert(sizeof(Canvas3DUniforms) == \(MemoryLayout<Canvas3DUniforms>.stride),
                          "Canvas3DUniforms layout drifted from Swift");
            static_assert(sizeof(Light3D) == \(MemoryLayout<Light3D>.stride),
                          "Light3D layout drifted from Swift");
            static_assert(sizeof(Material3D) == \(MemoryLayout<Material3D>.stride),
                          "Material3D layout drifted from Swift");
            static_assert(sizeof(ShadowFragmentUniforms) == \(MemoryLayout<ShadowFragmentUniforms>.stride),
                          "ShadowFragmentUniforms layout drifted from Swift");

            // 4 型すべてを組み込みと同じバインドスロットで受け取れることも見る。
            fragment float4 preludeStructsFragment(
                constant Canvas3DUniforms &uniforms [[buffer(1)]],
                constant Light3D *lights [[buffer(2)]],
                constant Material3D &material [[buffer(3)]],
                constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]]
            ) {
                float3 c = uniforms.color.rgb
                    + lights[0].colorAndIntensity.rgb
                    + material.ambientColor.rgb
                    + float3(shadowUniforms.shadowBias);
                return float4(c, 1.0);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "preludeStructsFragment") != nil)
    }

    // MARK: - ライティング関数

    @Test("canvas3DLightingFn で公開しているライティング関数の全シグネチャが解決する")
    func lightingFunctionsCompile() throws {
        // 引数 7 / 8（+shadow）/ 10（+IBL キューブ 2 枚）の 3 系統を、`calculateLighting` /
        // `calculatePBRLighting` / `calculateBlinnPhongLighting` の全部で呼ぶ。
        // どれか 1 つでも前文から落ちればここで落ちる。
        let source = """
            \(Self.stdlib)

            \(BuiltinShaders.canvas3DStructs)

            \(BuiltinShaders.canvas3DLightingFn)

            fragment float4 preludeLightingFragment(
                constant Canvas3DUniforms &uniforms [[buffer(1)]],
                constant Light3D *lights [[buffer(2)]],
                constant Material3D &material [[buffer(3)]],
                constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
                texture2d<float> shadowMap [[texture(1)]],
                texturecube<float> irradianceMap [[texture(2)]],
                texturecube<float> prefilteredMap [[texture(3)]]
            ) {
                float3 worldPos = float3(0.0, 0.0, 0.0);
                float3 normal = float3(0.0, 1.0, 0.0);
                float3 camera = uniforms.cameraPosition.xyz;
                float3 base = uniforms.color.rgb;
                uint count = uniforms.lightCount;

                if (metaphorSkipsLighting(material, count)) {
                    return uniforms.color;
                }

                constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge,
                                                compare_func::never);
                float shadow = calculateShadow(worldPos, shadowUniforms, shadowMap, shadowSampler);

                float3 acc = float3(0.0);
                acc += calculateLighting(worldPos, normal, camera, base, lights, count, material);
                acc += calculateLighting(worldPos, normal, camera, base, lights, count, material,
                                         shadow);
                acc += calculateLighting(worldPos, normal, camera, base, lights, count, material,
                                         shadow, irradianceMap, prefilteredMap);
                acc += calculatePBRLighting(worldPos, normal, camera, base, lights, count, material);
                acc += calculatePBRLighting(worldPos, normal, camera, base, lights, count, material,
                                            shadow);
                acc += calculatePBRLighting(worldPos, normal, camera, base, lights, count, material,
                                            shadow, irradianceMap, prefilteredMap);
                acc += calculateBlinnPhongLighting(worldPos, normal, camera, base, lights, count,
                                                   material);
                acc += calculateBlinnPhongLighting(worldPos, normal, camera, base, lights, count,
                                                   material, shadow);
                return float4(acc, 1.0);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "preludeLightingFragment") != nil)
    }

    // MARK: - 前文そのもの（#713）

    @Test("canvas3DPreamble だけでフラグメント関数が書ける")
    func preambleAloneIsEnough() throws {
        // `createMaterial()` がユーザーのソースへ足すのはこれ 1 つ。stage_in も
        // ライティング関数も含めて、これだけで最小のマテリアルが成立する。
        let source = """
            \(BuiltinShaders.canvas3DPreamble)

            fragment float4 preamblePreludeFragment(
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

        let library = try compile(source)
        #expect(library.makeFunction(name: "preamblePreludeFragment") != nil)
    }

    @Test("前文が二重に置かれてもコンパイルできる（ガードが効く）")
    func preambleIsIdempotent() throws {
        // `createMaterial()` は前文を必ず足すので、以前の作法で自分でも前置している
        // ソースでは前文が 2 回現れる。ガードが無いと構造体の二重定義で落ちる。
        let source = """
            \(BuiltinShaders.canvas3DPreamble)

            \(BuiltinShaders.canvas3DPreamble)

            fragment float4 doublePreludeFragment(
                Canvas3DVertexOut in [[stage_in]],
                constant Canvas3DUniforms &uniforms [[buffer(1)]]
            ) {
                return uniforms.color;
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "doublePreludeFragment") != nil)
    }

    // MARK: - 2D の前文（#647 / #714）

    @Test("canvas2DPreamble だけで 4 経路ぶんの stage_in が解決する")
    func canvas2DPreambleAloneIsEnough() throws {
        // `loadShader()` / `createShader()` がユーザーのソースへ足すのはこれ 1 つ。
        // `Canvas2DPipelineStore.makeCustom()` はユーザーのフラグメントを color /
        // instanced / massive / textured の組み込み頂点関数と組むので、カラー系
        // （3 経路で共通）とテクスチャ系の 2 つの stage_in が前文だけで書けること。
        let source = """
            \(BuiltinShaders.canvas2DPreamble)

            fragment float4 preludeColorFragment(
                Canvas2DVertexOut in [[stage_in]],
                constant Canvas2DShaderUniforms &u [[buffer(3)]]
            ) {
                float2 uv = in.position.xy / u.resolution;
                return float4(uv, u.time, 1.0) * in.color;
            }

            fragment float4 preludeTexturedFragment(
                Canvas2DTexVertexOut in [[stage_in]],
                texture2d<float> tex [[texture(0)]],
                constant Canvas2DShaderUniforms &u [[buffer(3)]]
            ) {
                constexpr sampler s(filter::linear);
                return tex.sample(s, in.texCoord + u.mouse / u.resolution) * in.color;
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "preludeColorFragment") != nil)
        #expect(library.makeFunction(name: "preludeTexturedFragment") != nil)
    }

    @Test("canvas2DStructs のレイアウトが Swift 側と一致する")
    func canvas2DStructsMatchSwiftLayout() throws {
        // `Canvas2DShaderUniforms` は metaphor が `buffer(3)` へ書き込む側と、ユーザーが
        // 読む側の両方をこの 1 つで賄う。Swift 側（`Drawing/Shader2D.swift`）と
        // `.h` のどちらかだけを直すと、カスタムシェーダが黙って別の値を読む。
        let source = """
            \(BuiltinShaders.canvas2DPreamble)

            static_assert(sizeof(Canvas2DShaderUniforms) == \(MemoryLayout<Canvas2DShaderUniforms>.stride),
                          "Canvas2DShaderUniforms layout drifted from Swift");

            fragment float4 canvas2DLayoutFragment(
                constant Canvas2DShaderUniforms &u [[buffer(3)]]
            ) {
                return float4(u.resolution, u.mouse.x, float(u.frameCount));
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "canvas2DLayoutFragment") != nil)
    }

    @Test("2D 前文も二重に置ける（ガードが効く）")
    func canvas2DPreambleIsIdempotent() throws {
        let source = """
            \(BuiltinShaders.canvas2DPreamble)

            \(BuiltinShaders.canvas2DPreamble)

            fragment float4 double2DFragment(
                Canvas2DVertexOut in [[stage_in]],
                constant Canvas2DShaderUniforms &u [[buffer(3)]]
            ) {
                return float4(in.position.xy / u.resolution, 0.0, 1.0);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "double2DFragment") != nil)
    }

    // MARK: - postFX の前文（#718）

    @Test("postProcessPreamble だけでフラグメント関数が書ける")
    func postProcessPreambleAloneIsEnough() throws {
        // `createPostEffect()` がユーザーのソースへ足すのはこれ 1 つ。stage_in も
        // 組み込みパラメータも含めて、これだけで最小のエフェクトが成立する。
        let source = """
            \(PostProcessShaders.postProcessPreamble)

            fragment float4 postPreludeFragment(
                PPVertexOut in [[stage_in]],
                texture2d<float> tex [[texture(0)]],
                constant PostProcessParams &params [[buffer(0)]]
            ) {
                constexpr sampler s(filter::linear);
                float4 color = tex.sample(s, in.texCoord + params.texelSize * params.intensity);
                return float4(1.0 - color.rgb, color.a);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "postPreludeFragment") != nil)
    }

    @Test("postFX 前文も二重に置ける（ガードが効く）")
    func postProcessPreambleIsIdempotent() throws {
        // `createPostEffect()` は前文を必ず足すので、以前の作法（`commonStructs` を
        // 自分で前置する）で書かれたソースでは前文が 2 回現れる。
        let source = """
            \(PostProcessShaders.postProcessPreamble)

            \(PostProcessShaders.commonStructs)

            fragment float4 doublePostPreludeFragment(
                PPVertexOut in [[stage_in]],
                constant PostProcessParams &params [[buffer(0)]]
            ) {
                return float4(in.texCoord, params.intensity, 1.0);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "doublePostPreludeFragment") != nil)
    }

    @Test("postProcessStructs のレイアウトが Swift 側と一致する")
    func postProcessStructsMatchSwiftLayout() throws {
        let source = """
            \(PostProcessShaders.postProcessPreamble)

            static_assert(sizeof(PostProcessParams) == \(MemoryLayout<PostProcessParams>.stride),
                          "PostProcessParams layout drifted from Swift");

            fragment float4 postLayoutFragment(
                constant PostProcessParams &params [[buffer(0)]]
            ) {
                return float4(params.texelSize, params.brightness, params.saturation);
            }
            """

        let library = try compile(source)
        #expect(library.makeFunction(name: "postLayoutFragment") != nil)
    }

    @Test("canvas3DStructs 抜きの canvas3DLightingFn は成立しない（前文は 2 つで 1 組）")
    func lightingFunctionsNeedStructs() {
        // 「構造体も入っているから前文は 1 つでよい」と誤解させないための固定。
        // 逆向き（構造体が二重定義になる）に振れても、ここが落ちて気付ける。
        let source = """
            \(Self.stdlib)

            \(BuiltinShaders.canvas3DLightingFn)
            """

        #expect(throws: (any Error).self) {
            _ = try compile(source)
        }
    }
}

// MARK: - 前文構造体のフィールドの並び（#1146）

/// カスタムシェーダへ配る前文の構造体を、Swift 側の実レイアウトと**フィールド単位で**突き合わせる。
///
/// 上の ``ShaderPreludeTests`` が持つ `static_assert(sizeof(...) == ...)` が見ているのは
/// **バイト数だけ**で、同じ型が隣り合っていると入れ替えが素通りする。#1146 で実測したところ、
/// `Canvas2DShaderUniforms` の `resolution` と `mouse` を入れ替えて生成物まで揃えても
/// `make ci-check` が exit 0 で通った（2159 tests passed / freshness も緑）。前文 6 型の
/// 隣接 31 か所のうち **26 か所**が `sizeof` では区別できない。
///
/// 並びがずれると**ユーザーのカスタムシェーダが黙って別の値を読む** —
/// `u.resolution` がマウス座標になり、`u.time` がフレーム数になる。コンパイルは通り、
/// 警告も出ない。とくに `Canvas2DShaderUniforms` は**組み込みシェーダーが 1 つも使わない**
/// ので、#1142 の `CircleInstance` にあった「描画テストが偶発的に拾う」保険すら無い。
///
/// ここは GPU を使わない。``ShaderPreludeTests`` は `MTLCreateSystemDefaultDevice()` が
/// 見えないとまるごと skip されるが、前文はただの文字列なので、GPU の無い環境でも
/// 契約を見る目が 1 つ残る。
///
/// 手で書くのは**フィールド名と MSL の型名だけ**で、offset と size は `MemoryLayout` から取る。
/// Swift 側を直せば期待値は自動で追従し、**MSL 側だけが動いたときに赤くなる**（両方が揃って
/// 動くのは正しい変更で、ユーザーのソースは実行時に現在の前文と一緒にコンパイルされるので
/// 影響が無い）。
@Suite("Shader Prelude Layout")
struct ShaderPreludeLayoutTests {

    // MARK: 2D（#291 のカスタムシェーダが読む側）

    @Test("Canvas2DShaderUniforms の並びが Swift 側と一致する")
    func canvas2DShaderUniformsLayout() throws {
        try Self.expectLayout(
            of: Canvas2DShaderUniforms.self,
            named: "Canvas2DShaderUniforms",
            in: BuiltinShaders.canvas2DStructs,
            origin: "BuiltinShaders.canvas2DStructs",
            fields: [
                Expectation("resolution", "float2", \Canvas2DShaderUniforms.resolution),
                Expectation("mouse", "float2", \Canvas2DShaderUniforms.mouse),
                Expectation("time", "float", \Canvas2DShaderUniforms.time),
                Expectation("frameCount", "uint", \Canvas2DShaderUniforms.frameCount),
            ])
    }

    // MARK: 3D（#713 のカスタムマテリアルが読む側）

    @Test("Canvas3DUniforms の並びが Swift 側と一致する")
    func canvas3DUniformsLayout() throws {
        try Self.expectLayout(
            of: Canvas3DUniforms.self,
            named: "Canvas3DUniforms",
            in: BuiltinShaders.canvas3DStructs,
            origin: "BuiltinShaders.canvas3DStructs",
            fields: [
                Expectation("modelMatrix", "float4x4", \Canvas3DUniforms.modelMatrix),
                Expectation(
                    "viewProjectionMatrix", "float4x4", \Canvas3DUniforms.viewProjectionMatrix),
                Expectation("normalMatrix", "float4x4", \Canvas3DUniforms.normalMatrix),
                Expectation("color", "float4", \Canvas3DUniforms.color),
                Expectation("cameraPosition", "float4", \Canvas3DUniforms.cameraPosition),
                Expectation("time", "float", \Canvas3DUniforms.time),
                Expectation("lightCount", "uint", \Canvas3DUniforms.lightCount),
                Expectation("hasTexture", "uint", \Canvas3DUniforms.hasTexture),
                Expectation("_pad", "uint", \Canvas3DUniforms._pad),
            ])
    }

    @Test("Light3D の並びが Swift 側と一致する")
    func light3DLayout() throws {
        try Self.expectLayout(
            of: Light3D.self,
            named: "Light3D",
            in: BuiltinShaders.canvas3DStructs,
            origin: "BuiltinShaders.canvas3DStructs",
            fields: [
                Expectation("positionAndType", "float4", \Light3D.positionAndType),
                Expectation("directionAndCutoff", "float4", \Light3D.directionAndCutoff),
                Expectation("colorAndIntensity", "float4", \Light3D.colorAndIntensity),
                Expectation(
                    "attenuationAndOuterCutoff", "float4", \Light3D.attenuationAndOuterCutoff),
            ])
    }

    @Test("Material3D の並びが Swift 側と一致する")
    func material3DLayout() throws {
        try Self.expectLayout(
            of: Material3D.self,
            named: "Material3D",
            in: BuiltinShaders.canvas3DStructs,
            origin: "BuiltinShaders.canvas3DStructs",
            fields: [
                Expectation("ambientColor", "float4", \Material3D.ambientColor),
                Expectation("specularAndShininess", "float4", \Material3D.specularAndShininess),
                Expectation("emissiveAndMetallic", "float4", \Material3D.emissiveAndMetallic),
                Expectation("pbrParams", "float4", \Material3D.pbrParams),
                Expectation("toneMapParams", "float4", \Material3D.toneMapParams),
            ])
    }

    @Test("ShadowFragmentUniforms の並びが Swift 側と一致する")
    func shadowFragmentUniformsLayout() throws {
        try Self.expectLayout(
            of: ShadowFragmentUniforms.self,
            named: "ShadowFragmentUniforms",
            in: BuiltinShaders.canvas3DStructs,
            origin: "BuiltinShaders.canvas3DStructs",
            fields: [
                Expectation(
                    "lightSpaceMatrix", "float4x4", \ShadowFragmentUniforms.lightSpaceMatrix),
                Expectation("shadowBias", "float", \ShadowFragmentUniforms.shadowBias),
                Expectation("shadowEnabled", "float", \ShadowFragmentUniforms.shadowEnabled),
                Expectation("_pad", "float2", \ShadowFragmentUniforms._pad),
            ])
    }

    // MARK: postFX（#718 のカスタムエフェクトが読む側）

    @Test("PostProcessParams の並びが Swift 側と一致する")
    func postProcessParamsLayout() throws {
        try Self.expectLayout(
            of: PostProcessParams.self,
            named: "PostProcessParams",
            in: PostProcessShaders.commonStructs,
            origin: "PostProcessShaders.commonStructs",
            fields: [
                Expectation("texelSize", "float2", \PostProcessParams.texelSize),
                Expectation("intensity", "float", \PostProcessParams.intensity),
                Expectation("threshold", "float", \PostProcessParams.threshold),
                Expectation("brightness", "float", \PostProcessParams.brightness),
                Expectation("contrast", "float", \PostProcessParams.contrast),
                Expectation("saturation", "float", \PostProcessParams.saturation),
                Expectation("temperature", "float", \PostProcessParams.temperature),
                Expectation("radius", "float", \PostProcessParams.radius),
                Expectation("smoothness", "float", \PostProcessParams.smoothness),
                Expectation("_pad0", "float", \PostProcessParams._pad0),
                Expectation("_pad1", "float", \PostProcessParams._pad1),
            ])
    }

    // MARK: - 突き合わせの実体

    /// MSL 側に期待する 1 フィールド。offset と size は Swift の実レイアウトから取る。
    struct Expectation {
        let name: String
        let mslType: String
        let offset: Int?
        let size: Int

        init<Root, Value>(_ name: String, _ mslType: String, _ keyPath: KeyPath<Root, Value>) {
            self.name = name
            self.mslType = mslType
            self.offset = MemoryLayout<Root>.offset(of: keyPath)
            self.size = MemoryLayout<Value>.size
        }
    }

    /// 前文から `struct <名前>` を読み、`Root` の実レイアウトと突き合わせる。
    ///
    /// offset と型名の**両方**を見る。`float4` → `float3` は MSL でも 16 バイト
    /// （`float3` は 12 ではない）なので offset も stride も動かず、型名を固定して初めて
    /// 赤くなる（`float` → `uint` に至ってはバイト幅まで同じで、解釈だけが変わる）。
    private static func expectLayout<Root>(
        of root: Root.Type,
        named structName: String,
        in prelude: String,
        origin: String,
        fields expected: [Expectation]
    ) throws {
        let layouts = try MSLStructReader.layouts(ofStructNamed: structName, in: prelude)

        // 個数の下限は「リーダが何も拾えなくなって常に緑」への保険。
        #expect(
            layouts.count == 1,
            "\(origin) から struct \(structName) を 1 つ読めるはずが \(layouts.count) 個だった")
        guard let layout = layouts.first else { return }

        #expect(
            layout.stride == MemoryLayout<Root>.stride,
            """
            \(origin): \(structName) の MSL の stride は \(layout.stride) だが Swift は \
            \(MemoryLayout<Root>.stride)（読めた並び: \(layout.summary)）
            """)
        #expect(
            layout.fields.count == expected.count,
            """
            \(origin): \(structName) の MSL は \(layout.fields.count) フィールドだが \
            期待は \(expected.count)（読めた並び: \(layout.summary)）
            """)

        for entry in expected {
            guard let field = layout.field(named: entry.name) else {
                Issue.record(
                    "\(origin): \(structName) に \(entry.name) が無い（読めた並び: \(layout.summary)）")
                continue
            }
            #expect(
                field.offset == entry.offset,
                """
                \(origin): \(structName).\(entry.name) は MSL で offset \(field.offset) だが \
                Swift は \(entry.offset.map(String.init) ?? "nil")（読めた並び: \(layout.summary)）
                """)
            #expect(
                field.type == entry.mslType,
                """
                \(origin): \(structName).\(entry.name) の MSL の型は \(field.type) だが \
                \(entry.mslType) であるべき（読めた並び: \(layout.summary)）
                """)
            // 型表と Swift 側のサイズが食い違ったら、それは検査側の取り違え。
            #expect(
                field.size == entry.size,
                """
                \(origin): \(structName).\(entry.name) は MSL の \(field.type) が \
                \(field.size) バイト、Swift は \(entry.size) バイト — \
                MSLStructReader.knownTypes を疑うこと
                """)
        }
    }
}
