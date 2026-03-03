#include "MetaphorShaderTypes.h"

struct VertexColorIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct VertexColorOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexColorOut metaphor_vertexColorVertex(
    VertexColorIn in [[stage_in]],
    constant MetaphorUniforms &uniforms [[buffer(1)]]
) {
    VertexColorOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.color = in.color;
    return out;
}

fragment float4 metaphor_vertexColorFragment(
    VertexColorOut in [[stage_in]]
) {
    return in.color;
}
