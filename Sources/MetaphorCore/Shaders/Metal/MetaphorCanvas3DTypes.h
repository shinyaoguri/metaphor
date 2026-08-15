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

#endif
