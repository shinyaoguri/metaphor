#include "MetaphorCanvas2DTypes.h"
#include "MetaphorCanvas2DBlend.h"

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
// Fragment shaders
// ──────────────────────────────────────────────

fragment float4 metaphor_canvas2DInstancedFragment(
    Canvas2DVertexOut in [[stage_in]]
) {
    return metaphorPremultiply(in.color);
}

// フレームバッファフェッチで合成するモード。式は `MetaphorCanvas2DBlend.h`。
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedMultiplyFragment, metaphorBlendMultiply)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedScreenFragment, metaphorBlendScreen)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedSubtractFragment, metaphorBlendSubtract)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedLightestFragment, metaphorBlendLightest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedDarkestFragment, metaphorBlendDarkest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedDifferenceFragment, metaphorBlendDifference)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DInstancedExclusionFragment, metaphorBlendExclusion)
