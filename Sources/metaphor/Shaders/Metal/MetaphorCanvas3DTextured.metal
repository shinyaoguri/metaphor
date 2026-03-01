#include "MetaphorShaderTypes.h"
#include "MetaphorLighting.h"

struct Canvas3DTexVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct Canvas3DTexVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
};

vertex Canvas3DTexVertexOut metaphor_canvas3DTexturedVertex(
    Canvas3DTexVertexIn in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]]
) {
    Canvas3DTexVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    return out;
}

fragment float4 metaphor_canvas3DTexturedFragment(
    Canvas3DTexVertexOut in [[stage_in]],
    constant Canvas3DUniforms &uniforms [[buffer(1)]],
    constant Light3D *lights [[buffer(2)]],
    constant Material3D &material [[buffer(3)]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::repeat);
    float4 texColor = tex.sample(s, in.uv);
    float4 tintedColor = texColor * uniforms.color;

    if (uniforms.lightCount == 0) {
        return tintedColor;
    }

    float3 lit = calculateLighting(
        in.worldPosition,
        in.normal,
        uniforms.cameraPosition.xyz,
        tintedColor.rgb,
        lights,
        uniforms.lightCount,
        material
    );

    return float4(lit, tintedColor.a);
}
