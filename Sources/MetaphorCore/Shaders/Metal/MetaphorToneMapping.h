#ifndef MetaphorToneMapping_h
#define MetaphorToneMapping_h

#include <metal_stdlib>
using namespace metal;

// トーンマッピング（Issue #706）
//
// 3D のライティング結果は物理量なので 1.0 を超えうるが、レンダーターゲットは
// `.bgra8Unorm`（LDR 8bit）なので、そのまま書き出すとハードクランプされて
// ハイライトが白く潰れる。ここで 0…1 へ写像してから書き出す。
//
// 掛かるのは **3D のライティング結果だけ**で、2D の描画には掛からない
// （3D の lit は物理量・2D の color は最終色、という非対称を明示的に採る）。

// Reinhard: x / (1 + x)。単純で色相が安定するが、中間調のコントラストは眠くなる。
static inline float3 metaphorToneMapReinhard(float3 x) {
    return x / (1.0 + x);
}

// ACES filmic 近似（Narkowicz 2015）。暗部を締めてハイライトを滑らかに丸めるため、
// 金属や強い光源のある絵で破綻しにくい。
static inline float3 metaphorToneMapACESFilmic(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// `mode` は `ToneMapMode` の rawValue（0 = none / 1 = reinhard / 2 = acesFilmic）。
//
// `exposure` は **モードに関わらず**トーンマップ前に掛かる。既定の 1.0 は恒等倍なので、
// `.none` のままなら結果は従来と完全に一致する。
static inline float3 metaphorApplyToneMap(float3 color, float mode, float exposure) {
    float3 c = color * exposure;
    if (mode > 1.5) return metaphorToneMapACESFilmic(c);
    if (mode > 0.5) return saturate(metaphorToneMapReinhard(c));
    return c;
}

#endif
