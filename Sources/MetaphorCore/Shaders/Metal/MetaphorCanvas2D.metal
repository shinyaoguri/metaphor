#include "MetaphorCanvas2DTypes.h"
#include "MetaphorCanvas2DBlend.h"

// `Canvas2DVertexIn` / `Canvas2DVertexOut` は `MetaphorCanvas2DTypes.h`（= カスタム
// 2D シェーダへ配る前文）にある。組み込みとカスタムで stage_in のレイアウトが
// ずれないよう、定義は 1 箇所に置く。

vertex Canvas2DVertexOut metaphor_canvas2DVertex(
    Canvas2DVertexIn in [[stage_in]],
    constant float4x4 &projection [[buffer(1)]]
) {
    Canvas2DVertexOut out;
    out.position = projection * float4(in.position, 0.0, 1.0);
    out.color = in.color;
    return out;
}

// 頂点色は straight で渡ってくる（fill / stroke がそのまま入る）。キャンバスの中身は
// premultiplied なので、ここで掛けてから返す（ADR-0012）。
fragment float4 metaphor_canvas2DFragment(
    Canvas2DVertexOut in [[stage_in]]
) {
    return metaphorPremultiply(in.color);
}

// フレームバッファフェッチで合成するモード。式は `MetaphorCanvas2DBlend.h`。
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DMultiplyFragment, metaphorBlendMultiply)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DScreenFragment, metaphorBlendScreen)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DSubtractFragment, metaphorBlendSubtract)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DLightestFragment, metaphorBlendLightest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DDarkestFragment, metaphorBlendDarkest)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DDifferenceFragment, metaphorBlendDifference)
METAPHOR_CANVAS2D_BLEND_FRAGMENT(metaphor_canvas2DExclusionFragment, metaphorBlendExclusion)
