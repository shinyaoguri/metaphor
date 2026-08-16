#ifndef MetaphorCanvas2DBlend_h
#define MetaphorCanvas2DBlend_h

#include "MetaphorCanvas2DTypes.h"

// 分離可能ブレンドモードの実装（ADR-0012 / #801）。
//
// `.multiply` / `.screen` / `.subtract` / `.lightest` / `.darkest` / `.difference` /
// `.exclusion` は固定関数のブレンド係数では書けない。src の α を「混ぜ方をどれだけ
// 効かせるか」として使うため、`mix(dst, blend(src, dst), src.a)` という**係数の積和に
// 乗らない形**が要るからで、そのためフレームバッファフェッチ（`float4 dest [[color(0)]]`）
// でキャンバスの値を読み、合成をここで行う。
//
// 式は W3C Compositing and Blending Level 1 の source-over + 分離可能ブレンド:
//
//     co = as·(1 − ab)·Cs + as·ab·B(Cb, Cs) + (1 − as)·ab·Cb
//     ao = as + ab·(1 − as)
//
// `co` は既に premultiplied なので、そのまま返せばキャンバスの規範（内部は
// premultiplied）に合う。下地が無い（ab = 0）ところでは `co = as·Cs` となり、
// 「混ぜる相手が無ければ src がそのまま出る」という素直な振る舞いになる。
//
// この経路のパイプラインは固定関数のブレンドを無効にしている（`BlendMode.apply(to:)`）。

// 範囲外の成分を飽和させる（`Color` は範囲外を保持し、飽和は描画時の約束）。
inline float4 metaphorClampSrc2D(float4 c) { return clamp(c, 0.0, 1.0); }

// ブレンド関数 B(Cb, Cs)。引数はどちらも straight。
inline float3 metaphorBlendMultiply(float3 Cs, float3 Cb) { return Cs * Cb; }
inline float3 metaphorBlendScreen(float3 Cs, float3 Cb) { return Cs + Cb - Cs * Cb; }
inline float3 metaphorBlendSubtract(float3 Cs, float3 Cb) { return max(Cb - Cs, 0.0); }
inline float3 metaphorBlendLightest(float3 Cs, float3 Cb) { return max(Cs, Cb); }
inline float3 metaphorBlendDarkest(float3 Cs, float3 Cb) { return min(Cs, Cb); }
inline float3 metaphorBlendDifference(float3 Cs, float3 Cb) { return abs(Cs - Cb); }
inline float3 metaphorBlendExclusion(float3 Cs, float3 Cb) {
    return Cs + Cb - 2.0 * Cs * Cb;
}

// src（straight）と dest（premultiplied）とブレンド結果から、premultiplied な出力を作る。
// src は `metaphorClampSrc2D` で飽和済みのものを渡すこと。
inline float4 metaphorComposite2D(float4 src, float4 dest, float3 blended) {
    float as = src.a;
    float ab = dest.a;
    float3 Cb = metaphorUnpremultiply(dest).rgb;
    float3 co = as * (1.0 - ab) * src.rgb + as * ab * blended + (1.0 - as) * ab * Cb;
    return float4(co, as + ab * (1.0 - as));
}

// カラー経路（color / instanced / massive）のブレンドフラグメントを 1 本作る。
// 3 経路は `Canvas2DVertexOut` を共有するので、本体はまったく同じになる。
#define METAPHOR_CANVAS2D_BLEND_FRAGMENT(NAME, BLEND_FN)                             \
    fragment float4 NAME(                                                            \
        Canvas2DVertexOut in [[stage_in]],                                           \
        float4 dest [[color(0)]]                                                     \
    ) {                                                                              \
        float4 src = metaphorClampSrc2D(in.color);                                   \
        float3 Cb = metaphorUnpremultiply(dest).rgb;                                 \
        return metaphorComposite2D(src, dest, BLEND_FN(src.rgb, Cb));                \
    }

// 既に straight なテクスチャ（`pixels` / `updatePixels()`。ADR-0012 / #848）用の
// 恒等デコード。`METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT_IMPL` へ渡す。
inline float4 metaphorKeepStraight(float4 c) { return c; }

// テクスチャ経路（`image()` / `text()` / `updatePixels()`）のブレンドフラグメント。
// 合成の式は経路によらず同じで、違うのは**サンプル値をどう straight にするか**だけ
// なので、そこだけ `DECODE` で差し替える。
#define METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT_IMPL(NAME, BLEND_FN, DECODE)       \
    fragment float4 NAME(                                                            \
        Canvas2DTexVertexOut in [[stage_in]],                                        \
        texture2d<float> tex [[texture(0)]],                                         \
        float4 dest [[color(0)]]                                                     \
    ) {                                                                              \
        constexpr sampler s(filter::linear, address::clamp_to_edge);                 \
        float4 texColor = DECODE(tex.sample(s, in.texCoord));                        \
        float4 src = metaphorClampSrc2D(texColor * in.color);                        \
        float3 Cb = metaphorUnpremultiply(dest).rgb;                                 \
        return metaphorComposite2D(src, dest, BLEND_FN(src.rgb, Cb));                \
    }

// テクスチャが premultiplied で入ってくる既定の経路（グリフアトラス・読み込んだ
// 画像・オフスクリーン）。straight に戻してから頂点色を掛ける。
#define METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT(NAME, BLEND_FN)                    \
    METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT_IMPL(NAME, BLEND_FN, metaphorUnpremultiply)

// テクスチャが既に straight で入ってくる経路（`updatePixels()`）。割り戻さない。
#define METAPHOR_CANVAS2D_STRAIGHT_TEXTURED_BLEND_FRAGMENT(NAME, BLEND_FN)           \
    METAPHOR_CANVAS2D_TEXTURED_BLEND_FRAGMENT_IMPL(NAME, BLEND_FN, metaphorKeepStraight)

#endif
