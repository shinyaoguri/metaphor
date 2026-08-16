#include "MetaphorCanvas2DTypes.h"
#include "MetaphorCanvas2DBlend.h"

// `Canvas2DTexVertexIn` / `Canvas2DTexVertexOut` は `MetaphorCanvas2DTypes.h`（= カスタム
// 2D シェーダへ配る前文）にある。

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

// テクスチャは premultiplied で入ってくる（グリフアトラスは `premultipliedLast` で焼かれ、
// 読み込んだ画像は `MTKTextureLoader` が、オフスクリーンは `.alpha` 合成がそうする）。
// 一方 `in.color`（tint / fill）は straight なので、**掛ける前に straight へ戻す**。
// 戻さずに掛けると α が二重に乗り、文字の AA が二乗され半透明画像が暗く沈む
//（ADR-0012 / #846 / #847）。返す値は再び premultiplied。
fragment float4 metaphor_canvas2DTexturedFragment(
    Canvas2DTexVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 texColor = metaphorUnpremultiply(tex.sample(s, in.texCoord));
    return metaphorPremultiply(texColor * in.color);
}

// `pixels` / `updatePixels()` 用（ADR-0012 / #848）。こちらのテクスチャは
// **straight で入ってくる** — `loadPixels()` が読み戻しのあと割り戻し、利用者は
// `color(r, g, b, a)`（straight を詰める helper）で書くため。割り戻さずに
// 頂点色を掛け、premultiplied にして返す。
fragment float4 metaphor_canvas2DStraightTexturedFragment(
    Canvas2DTexVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 texColor = tex.sample(s, in.texCoord);
    return metaphorPremultiply(texColor * in.color);
}

// フレームバッファフェッチで合成するモード。式は `MetaphorCanvas2DBlend.h`。
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedMultiplyFragment, metaphorBlendMultiply)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedScreenFragment, metaphorBlendScreen)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedSubtractFragment, metaphorBlendSubtract)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedLightestFragment, metaphorBlendLightest)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedDarkestFragment, metaphorBlendDarkest)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedDifferenceFragment, metaphorBlendDifference)
METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DTexturedExclusionFragment, metaphorBlendExclusion)

// straight なテクスチャ側のフェッチ経路。`updatePixels()` は現在のブレンドモードに
// 従って描くので、分離可能ブレンドも同数だけ要る。
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedMultiplyFragment, metaphorBlendMultiply)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedScreenFragment, metaphorBlendScreen)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedSubtractFragment, metaphorBlendSubtract)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedLightestFragment, metaphorBlendLightest)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedDarkestFragment, metaphorBlendDarkest)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedDifferenceFragment, metaphorBlendDifference)
METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(
    metaphor_canvas2DStraightTexturedExclusionFragment, metaphorBlendExclusion)
