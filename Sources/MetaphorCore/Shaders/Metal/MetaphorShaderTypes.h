#ifndef MetaphorShaderTypes_h
#define MetaphorShaderTypes_h

#include <metal_stdlib>
using namespace metal;

// 基本3Dシェーダー（flatColor / lit / vertexColor）用ユニフォーム。
// Canvas3D 系の構造体は `MetaphorCanvas3DTypes.h` にある。
struct MetaphorUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4 color;
    float3 lightDirection;
    float time;
};

#endif
