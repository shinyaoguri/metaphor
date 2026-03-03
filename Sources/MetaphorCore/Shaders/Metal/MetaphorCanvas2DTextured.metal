#include <metal_stdlib>
using namespace metal;

struct Canvas2DTexVertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct Canvas2DTexVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex Canvas2DTexVertexOut metaphor_canvas2DTexturedVertex(
    Canvas2DTexVertexIn in [[stage_in]],
    constant float4x4 &projection [[buffer(1)]]
) {
    Canvas2DTexVertexOut out;
    out.position = projection * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;
    return out;
}

fragment float4 metaphor_canvas2DTexturedFragment(
    Canvas2DTexVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 texColor = tex.sample(s, in.texCoord);
    return texColor * in.color;
}

fragment float4 metaphor_canvas2DTexturedDifferenceFragment(
    Canvas2DTexVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    float4 dest [[color(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 src = tex.sample(s, in.texCoord) * in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = abs(src.rgb - dest.rgb);
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}

fragment float4 metaphor_canvas2DTexturedExclusionFragment(
    Canvas2DTexVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    float4 dest [[color(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 src = tex.sample(s, in.texCoord) * in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}
