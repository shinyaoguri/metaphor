#include "MetaphorShaderTypes.h"

struct LitVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct LitVertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
    float3 worldPosition;
};

vertex LitVertexOut metaphor_litVertex(
    LitVertexIn in [[stage_in]],
    constant MetaphorUniforms &uniforms [[buffer(1)]]
) {
    LitVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.color = in.color * uniforms.color;
    return out;
}

fragment float4 metaphor_litFragment(
    LitVertexOut in [[stage_in]],
    constant MetaphorUniforms &uniforms [[buffer(1)]]
) {
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightDirection);

    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    return float4(in.color.rgb * lighting, in.color.a);
}
