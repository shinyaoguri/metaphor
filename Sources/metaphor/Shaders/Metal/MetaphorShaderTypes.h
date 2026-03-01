#ifndef MetaphorShaderTypes_h
#define MetaphorShaderTypes_h

#include <metal_stdlib>
using namespace metal;

// 基本3Dシェーダー用ユニフォーム
struct MetaphorUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4 color;
    float3 lightDirection;
    float time;
};

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
};

#endif
