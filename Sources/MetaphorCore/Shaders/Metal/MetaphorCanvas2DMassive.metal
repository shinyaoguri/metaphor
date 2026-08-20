#include "MetaphorCanvas2DTypes.h"
#include "MetaphorCanvas2DBlend.h"

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

// 頂点出力は `Canvas2DVertexOut`（`MetaphorCanvas2DTypes.h`）を使う。カスタム
// フラグメントはこの経路の頂点関数とも組まれるので、カラー経路と同じ型でなければ
// ならない。

vertex Canvas2DVertexOut metaphor_canvas2DMassiveCircleVertex(
    Canvas2DMassiveVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    device const CircleInstance *instances [[buffer(6)]],
    constant float4x4 &projection [[buffer(1)]],
    constant float4x4 &transform [[buffer(2)]]
) {
    Canvas2DVertexOut out;
    CircleInstance inst = instances[instanceID];
    float2 localPos = inst.position + in.position * inst.diameter;
    float4 worldPos = transform * float4(localPos, 0.0, 1.0);
    out.position = projection * worldPos;
    out.color = inst.color;
    return out;
}

fragment float4 metaphor_canvas2DMassiveFragment(
    Canvas2DVertexOut in [[stage_in]]
) {
    return metaphorPremultiply(in.color);
}

// フレームバッファフェッチで合成するモード。式は `MetaphorCanvas2DBlend.h`。
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveMultiplyFragment, metaphorBlendMultiply)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveScreenFragment, metaphorBlendScreen)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveSubtractFragment, metaphorBlendSubtract)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveLightestFragment, metaphorBlendLightest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveDarkestFragment, metaphorBlendDarkest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveDifferenceFragment, metaphorBlendDifference)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMassiveExclusionFragment, metaphorBlendExclusion)
