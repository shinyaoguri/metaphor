#include "MetaphorShaderTypes.h"
#include "MetaphorLighting.h"

struct Canvas3DVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct Canvas3DVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 color;
};

vertex Canvas3DVertexOut metaphor_canvas3DVertex(
    Canvas3DVertexIn in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]]
) {
    Canvas3DVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.color = in.color * uniforms.color;
    return out;
}

// ワイヤーフレーム（stroke）専用の頂点シェーダー。
//
// 通常の頂点シェーダーは頂点カラー（beginShape が記録時に焼き込む fill 色や
// メッシュ固有の頂点カラー）に uniforms.color を乗算する。stroke は
// strokeColor 単色で描かれるべきなのに、この乗算のせいで fill 色が混ざり、
// 補色関係（青い fill × 赤い stroke など）では黒くなって線が消えていた（#429）。
// ワイヤーパスでは頂点カラーを無視し uniforms.color をそのまま使う。
vertex Canvas3DVertexOut metaphor_canvas3DWireVertex(
    Canvas3DVertexIn in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]]
) {
    Canvas3DVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.color = uniforms.color;
    return out;
}

fragment float4 metaphor_canvas3DFragment(
    Canvas3DVertexOut in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]],
    constant Light3D *lights [[buffer(2)]],
    constant Material3D &material [[buffer(3)]],
    constant ShadowFragmentUniforms &shadowUniforms [[buffer(5)]],
    texture2d<float> shadowMap [[texture(1)]],
    texturecube<float> irradianceMap [[texture(2)]],
    texturecube<float> prefilteredMap [[texture(3)]]
) {
    if (metaphorSkipsLighting(material, uniforms.lightCount)) {
        return in.color;
    }

    // 影は直接光にのみ掛ける（ambient / emissive / AO は影の中でも保つ, #364）。
    // インスタンス経路と同じ計算をここでも行う。非インスタンス（イミディエイト）
    // 経路はバインドだけしてシェーダーが無視しており、影が落ちなかった（#391）。
    constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::never);
    float shadow = calculateShadow(in.worldPosition, shadowUniforms, shadowMap, shadowSampler);

    float3 lit = calculateLighting(
        in.worldPosition,
        in.normal,
        uniforms.cameraPosition.xyz,
        in.color.rgb,
        lights,
        uniforms.lightCount,
        material,
        shadow,
        irradianceMap,
        prefilteredMap
    );

    return float4(lit, in.color.a);
}
