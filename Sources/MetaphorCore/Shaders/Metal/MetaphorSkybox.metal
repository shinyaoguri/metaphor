#include <metal_stdlib>
#include "MetaphorToneMapping.h"
using namespace metal;

// skybox（環境の背景描画）。
//
// 頂点バッファを持たず `[[vertex_id]]` からフルスクリーンのクワッドを作り、
// 深度 1.0（NDC の最奥）に置いて `lessEqual` で描く。3D ジオメトリが書いた場所は
// 深度が 1.0 未満なので通らず、何も描かれていない画素にだけ環境が出る。
//
// レイ方向は逆ビュー射影行列で NDC を逆投影して求めるので、投影が透視でも正射でも、
// Processing 由来の flipY が入っていても、そのまま正しい向きになる。

struct SkyboxUniforms {
    float4x4 inverseViewProjection;
    float4 cameraPosition;   // xyz = カメラ位置
    float4 params;           // x=強度, y=トーンマップモード, z=露出, w=予約
};

struct SkyboxVertexOut {
    float4 position [[position]];
    float2 ndc;
};

vertex SkyboxVertexOut metaphor_skyboxVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
    };

    SkyboxVertexOut out;
    out.ndc = positions[vertexID];
    // z = w = 1 → 深度 1.0（最奥）
    out.position = float4(positions[vertexID], 1.0, 1.0);
    return out;
}

fragment float4 metaphor_skyboxFragment(
    SkyboxVertexOut in [[stage_in]],
    constant SkyboxUniforms &uniforms [[buffer(0)]],
    texturecube<float> envMap [[texture(0)]]
) {
    constexpr sampler envSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float4 farPoint = uniforms.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
    float3 worldPos = farPoint.xyz / farPoint.w;
    float3 dir = normalize(worldPos - uniforms.cameraPosition.xyz);

    float3 color = envMap.sample(envSampler, dir).rgb * uniforms.params.x;
    color = metaphorApplyToneMap(color, uniforms.params.y, uniforms.params.z);

    return float4(color, 1.0);
}
