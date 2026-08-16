#ifndef MetaphorCanvas2DTypes_h
#define MetaphorCanvas2DTypes_h

#include <metal_stdlib>
using namespace metal;

// Canvas2D の頂点入出力と、カスタムシェーダへ配る組み込み uniform。Swift 側の正本は
// 頂点が `Drawing/Canvas2D.swift`（`Vertex2D` / `TexturedVertex2D`）、uniform が
// `Drawing/Shader2D.swift`（`Canvas2DShaderUniforms`）。
//
// このヘッダはそのまま `BuiltinShaders.canvas2DStructs` として、ユーザーの
// カスタム 2D シェーダへ配られる（`scripts/generate-shader-sources.py` が生成）。
// **中身を変えると公開される前文も変わる**ので、フィールドの増減は Swift 側と
// `ShaderPreludeTests` のレイアウト検査に必ず揃えること。

// カラー系（`rect()` / `circle()` / `line()` など）の頂点入力。
struct Canvas2DVertexIn {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

// カラー系の頂点出力 = カスタムフラグメントシェーダの `[[stage_in]]`。
//
// `Canvas2DPipelineStore` はユーザーのフラグメントを color / instanced / massive の
// **どの経路の組み込み頂点関数とも組む**ので、3 経路の頂点出力はこの 1 型に揃えてある。
// ずれてもパイプライン生成が失敗して組み込みの絵へ静かに落ちるだけなので、
// 定義を分けないこと。
struct Canvas2DVertexOut {
    float4 position [[position]];
    float4 color;
};

// テクスチャ系（`image()` / `text()`）の頂点入力。
struct Canvas2DTexVertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

// テクスチャ系の頂点出力 = テクスチャ経路のカスタムフラグメントの `[[stage_in]]`。
struct Canvas2DTexVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

// metaphor が `buffer(3)` へ自動供給する組み込み uniform。
//
// 組み込みシェーダーは使わない（カスタムシェーダ専用）が、Swift 側とレイアウトを
// 突き合わせる先が必要なのでここに置く。2D のカラー頂点は UV を持たないので、UV は
// フラグメントの `[[position]]`（画面ピクセル座標）を `resolution` で割って作る。
struct Canvas2DShaderUniforms {
    float2 resolution;
    float2 mouse;
    float time;
    uint frameCount;
};

// アルファの変換ヘルパ（ADR-0012）。
//
// metaphor は**公開 API が straight alpha、内部が premultiplied alpha**という規範を
// 採っている。`in.color`（fill / tint 由来）は straight で渡ってくるが、
// **フラグメントが返す値は premultiplied でなければならない**。キャンバスの中身が
// premultiplied だからで、straight のまま返すと合成のたびに α が二重に掛かる。
//
// カスタム 2D フラグメントの最後は次の形にする:
//
//     return metaphorPremultiply(float4(rgb, alpha));
//
// 不透明（alpha = 1）しか返さないシェーダは premultiplied と straight が一致するので、
// そのままで構わない。
//
// 成分は掛ける前に 0...1 へ飽和させる。`Color` は範囲外の値を保持する仕様（Tween の
// オーバーシュートなど）で、「描画時に飽和する」ことを doc が保証しているため。
// 以前は GPU がフラグメント出力をブレンド前にクランプすることでこれが成立していたが、
// α を自分で掛けるようになると `a = 1.5` が色を 1.5 倍してしまう。
inline float4 metaphorPremultiply(float4 c) {
    float4 s = clamp(c, 0.0, 1.0);
    return float4(s.rgb * s.a, s.a);
}

// premultiplied → straight。α = 0 の画素は色を持たないので黒を返す。
inline float4 metaphorUnpremultiply(float4 c) {
    return c.a > 0.0 ? float4(c.rgb / c.a, c.a) : float4(0.0);
}

#endif
