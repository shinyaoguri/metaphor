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

fragment float4 metaphor_canvas3DFragment(
    Canvas3DVertexOut in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]],
    constant Light3D *lights [[buffer(2)]],
    constant Material3D &material [[buffer(3)]]
) {
    if (uniforms.lightCount == 0) {
        return in.color;
    }

    float3 lit = calculateLighting(
        in.worldPosition,
        in.normal,
        uniforms.cameraPosition.xyz,
        in.color.rgb,
        lights,
        uniforms.lightCount,
        material
    );

    return float4(lit, in.color.a);
}
