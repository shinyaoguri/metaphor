#include <metal_stdlib>
using namespace metal;

// Per-circle instance data (32 bytes, 16-byte aligned).
struct CircleInstance {
    float2 position;
    float diameter;
    float _pad;
    float4 color;
};

struct Canvas2DMassiveVertexIn {
    float2 position [[attribute(0)]];
};

struct Canvas2DMassiveVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex Canvas2DMassiveVertexOut metaphor_canvas2DMassiveCircleVertex(
    Canvas2DMassiveVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    device const CircleInstance *instances [[buffer(6)]],
    constant float4x4 &projection [[buffer(1)]],
    constant float4x4 &transform [[buffer(2)]]
) {
    Canvas2DMassiveVertexOut out;
    CircleInstance inst = instances[instanceID];
    float2 localPos = inst.position + in.position * inst.diameter;
    float4 worldPos = transform * float4(localPos, 0.0, 1.0);
    out.position = projection * worldPos;
    out.color = inst.color;
    return out;
}

fragment float4 metaphor_canvas2DMassiveFragment(
    Canvas2DMassiveVertexOut in [[stage_in]]
) {
    return in.color;
}

fragment float4 metaphor_canvas2DMassiveDifferenceFragment(
    Canvas2DMassiveVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = abs(src.rgb - dest.rgb);
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}

fragment float4 metaphor_canvas2DMassiveExclusionFragment(
    Canvas2DMassiveVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}
