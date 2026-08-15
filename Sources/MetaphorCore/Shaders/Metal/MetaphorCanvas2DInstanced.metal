#include "MetaphorCanvas2DTypes.h"

// Per-instance data (80 bytes, 16-byte aligned)
struct InstanceData2D {
    float4x4 transform;  // 2D affine embedded in 4x4
    float4 color;         // RGBA
};

struct Canvas2DInstancedVertexIn {
    float2 position [[attribute(0)]];
};

// 頂点出力は `Canvas2DVertexOut`（`MetaphorCanvas2DTypes.h`）を使う。カスタム
// フラグメントはこの経路の頂点関数とも組まれるので、カラー経路と同じ型でなければ
// ならない。

// ──────────────────────────────────────────────
// Vertex shader
// ──────────────────────────────────────────────

vertex Canvas2DVertexOut metaphor_canvas2DInstancedVertex(
    Canvas2DInstancedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    device const InstanceData2D *instances [[buffer(6)]],
    constant float4x4 &projection [[buffer(1)]]
) {
    Canvas2DVertexOut out;
    InstanceData2D inst = instances[instanceID];
    float4 worldPos = inst.transform * float4(in.position, 0.0, 1.0);
    out.position = projection * worldPos;
    out.color = inst.color;
    return out;
}

// ──────────────────────────────────────────────
// Fragment shaders (3 variants for blend modes)
// ──────────────────────────────────────────────

fragment float4 metaphor_canvas2DInstancedFragment(
    Canvas2DVertexOut in [[stage_in]]
) {
    return in.color;
}

fragment float4 metaphor_canvas2DInstancedDifferenceFragment(
    Canvas2DVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = abs(src.rgb - dest.rgb);
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}

fragment float4 metaphor_canvas2DInstancedExclusionFragment(
    Canvas2DVertexOut in [[stage_in]],
    float4 dest [[color(0)]]
) {
    float4 src = in.color;
    float a = src.a + dest.a * (1.0 - src.a);
    float3 blended = src.rgb + dest.rgb - 2.0 * src.rgb * dest.rgb;
    float3 result = mix(dest.rgb, blended, src.a);
    return float4(result, a);
}
