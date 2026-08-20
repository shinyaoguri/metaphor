#ifndef MetaphorPBR_h
#define MetaphorPBR_h

#include <metal_stdlib>
using namespace metal;

// GGX/Trowbridge-Reitz Normal Distribution Function
static inline float DistributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;

    return a2 / max(denom, 0.0000001);
}

// Schlick-GGX Geometry function (single direction)
static inline float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

// Smith's method combining both view and light directions
static inline float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

// Fresnel-Schlick approximation
static inline float3 FresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// 粗さを考慮した Fresnel-Schlick。環境（IBL）項では入射方向が半球全体に広がるため、
// 直接光用の ``FresnelSchlick`` をそのまま使うと粗い面の縁が過剰に光る。
static inline float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    float3 maxF = max(float3(1.0 - roughness), F0);
    return F0 + (maxF - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// split-sum 近似の第 2 項（環境 BRDF）の解析近似。
//
// 一般的な実装は 2ch の LUT テクスチャを焼くが、Karis / Lazarov の多項式近似で
// 置き換えている（テクスチャ 1 枚・ベイクパス 1 本・バインドスロット 1 つを削れて、
// 見た目の差はほぼ無い）。戻り値は (scale, bias) で `F * scale + bias` として使う。
static inline float2 EnvBRDFApprox(float NdotV, float roughness) {
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}

// IBL（image-based lighting）の寄与。
//
// 拡散はコサイン畳み込み済みのイラディアンスキューブ、鏡面は roughness ごとに
// GGX でプリフィルタしたキューブの mip を引く（split-sum 近似）。`intensity` が
// 0 のとき（= `environment()` 未設定）は完全に 0 を返すので、環境なしの絵は不変。
static inline float3 metaphorIBLContribution(
    float3 N,
    float3 V,
    float3 baseColor,
    float metallic,
    float roughness,
    float ao,
    float intensity,
    texturecube<float> irradianceMap,
    texturecube<float> prefilteredMap
) {
    if (intensity <= 0.0) return float3(0.0);

    constexpr sampler envSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float NdotV = max(dot(N, V), 0.0);
    float3 F0 = mix(float3(0.04), baseColor, metallic);
    float3 F = FresnelSchlickRoughness(NdotV, F0, roughness);
    // エネルギー保存: 金属には拡散が無い
    float3 kD = (1.0 - F) * (1.0 - metallic);

    float3 irradiance = irradianceMap.sample(envSampler, N).rgb;
    float3 diffuse = irradiance * baseColor;

    float3 R = reflect(-V, N);
    float mipCount = float(max(prefilteredMap.get_num_mip_levels(), 1u));
    float lod = clamp(roughness, 0.0, 1.0) * (mipCount - 1.0);
    float3 prefiltered = prefilteredMap.sample(envSampler, R, level(lod)).rgb;

    float2 ab = EnvBRDFApprox(NdotV, roughness);
    float3 specular = prefiltered * (F * ab.x + ab.y);

    return (kD * diffuse + specular) * ao * intensity;
}

#endif
