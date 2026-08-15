import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore

/// カスタムマテリアルシェーダ用の前文（``BuiltinShaders/canvas3DStructs`` /
/// ``BuiltinShaders/canvas3DLightingFn``）を、実際に MSL としてコンパイルして固定する。
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
