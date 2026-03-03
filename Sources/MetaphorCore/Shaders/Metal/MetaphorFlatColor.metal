#include "MetaphorShaderTypes.h"

struct FlatColorVertexIn {
    float3 position [[attribute(0)]];
};

struct FlatColorVertexOut {
    float4 position [[position]];
};

vertex FlatColorVertexOut metaphor_flatColorVertex(
    FlatColorVertexIn in [[stage_in]],
    constant MetaphorUniforms &uniforms [[buffer(1)]]
) {
    FlatColorVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    return out;
}

fragment float4 metaphor_flatColorFragment(
    FlatColorVertexOut in [[stage_in]],
    constant MetaphorUniforms &uniforms [[buffer(1)]]
) {
    return uniforms.color;
}
