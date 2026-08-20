#ifndef MetaphorCanvas3DTypes_h
#define MetaphorCanvas3DTypes_h

#include <metal_stdlib>
using namespace metal;

// Canvas3D が GPU へ渡す構造体。Swift 側の正本は `Drawing/Canvas3DTypes.swift`
// （`ShadowFragmentUniforms` だけ `Drawing/ShadowMap.swift`）。
//
// このヘッダはそのまま `BuiltinShaders.canvas3DStructs` として、ユーザーの
// カスタムマテリアルシェーダーへ配られる（`scripts/generate-shader-sources.py`
// が生成）。**中身を変えると公開される前文も変わる**ので、フィールドの増減は
// Swift 側と `ShaderPreludeTests` のレイアウト検査に必ず揃えること。

// Canvas3D ユニフォーム
struct Canvas3DUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 normalMatrix;
    float4 color;
    float4 cameraPosition;
    float time;
    uint lightCount;
    uint hasTexture;
    uint _pad;
};

// ライト
struct Light3D {
    float4 positionAndType;
    float4 directionAndCutoff;
    float4 colorAndIntensity;
    float4 attenuationAndOuterCutoff;
};

// マテリアル
struct Material3D {
    float4 ambientColor;
    float4 specularAndShininess;
    float4 emissiveAndMetallic;
    float4 pbrParams;             // x=roughness, y=usePBR(0/1), z=ao, w=reserved
    float4 toneMapParams;         // x=toneMapMode, y=exposure, z=envIntensity(IBL), w=reserved
};

// シャドウフラグメントユニフォーム
struct ShadowFragmentUniforms {
    float4x4 lightSpaceMatrix;
    float shadowBias;
    float shadowEnabled;
    float2 _pad;
};

// 頂点シェーダーの入力（頂点バッファのレイアウト）。カスタム頂点シェーダーを
// 書くときの `[[stage_in]]` にあたる。
struct Canvas3DVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

// 組み込み頂点シェーダーの出力 = カスタムフラグメントシェーダーの `[[stage_in]]`。
// 組み込みの頂点シェーダーをそのまま使うなら、この型で受け取る。
struct Canvas3DVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 color;
};

// テクスチャ経路（`texture()` 適用時）の頂点入力。
struct Canvas3DTexVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

// テクスチャ経路の `[[stage_in]]`。頂点カラーの代わりに UV を持つ。
struct Canvas3DTexVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
};

#endif
