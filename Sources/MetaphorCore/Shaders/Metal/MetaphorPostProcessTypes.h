#ifndef MetaphorPostProcessTypes_h
#define MetaphorPostProcessTypes_h

#include <metal_stdlib>
using namespace metal;

// ポストプロセスが GPU へ渡す構造体。Swift 側の正本は `PostProcess/PostEffect.swift`
// （`PostProcessParams`）。
//
// このヘッダはそのまま `PostProcessShaders.commonStructs` として、ユーザーの
// カスタムポストエフェクトへ配られる（`scripts/generate-shader-sources.py` が生成）。
// **中身を変えると公開される前文も変わる**ので、フィールドの増減は Swift 側と
// `ShaderPreludeTests` のレイアウト検査に必ず揃えること。

// 組み込みのポストプロセス頂点シェーダーの出力 = カスタムフラグメントシェーダーの
// `[[stage_in]]`。`texCoord` は 0〜1 の画面座標。
struct PPVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// metaphor が `buffer(0)` へ自動供給する組み込みパラメータ。
struct PostProcessParams {
    float2 texelSize;
    float  intensity;
    float  threshold;
    float  brightness;
    float  contrast;
    float  saturation;
    float  temperature;
    float  radius;
    float  smoothness;
    float  _pad0;
    float  _pad1;
};

#endif
