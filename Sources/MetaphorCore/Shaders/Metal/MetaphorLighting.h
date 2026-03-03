#ifndef MetaphorLighting_h
#define MetaphorLighting_h

#include "MetaphorShaderTypes.h"
#include "MetaphorPBR.h"

// シャドウフラグメントユニフォーム
struct ShadowFragmentUniforms {
    float4x4 lightSpaceMatrix;
    float shadowBias;
    float shadowEnabled;
    float2 _pad;
};

// PCF ソフトシャドウ計算
static inline float calculateShadow(
    float3 worldPos,
    constant ShadowFragmentUniforms &shadowUniforms,
    texture2d<float> shadowMap,
    sampler shadowSampler
) {
    if (shadowUniforms.shadowEnabled < 0.5) return 1.0;

    float4 lightSpacePos = shadowUniforms.lightSpaceMatrix * float4(worldPos, 1.0);
    float3 projCoords = lightSpacePos.xyz / lightSpacePos.w;

    // NDC → [0,1] テクスチャ座標
    float2 shadowUV = projCoords.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y;  // Metal テクスチャ座標は上が0

    // 範囲外はシャドウなし
    if (shadowUV.x < 0 || shadowUV.x > 1 || shadowUV.y < 0 || shadowUV.y > 1) return 1.0;

    float currentDepth = projCoords.z;
    if (currentDepth > 1.0) return 1.0;

    float bias = shadowUniforms.shadowBias;

    // 3x3 PCF
    float shadow = 0.0;
    float2 texelSize = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closestDepth = shadowMap.sample(shadowSampler, shadowUV + float2(x, y) * texelSize).r;
            shadow += (currentDepth - bias > closestDepth) ? 0.0 : 1.0;
        }
    }
    return shadow / 9.0;
}

// PBR (Cook-Torrance GGX) ライティング
static inline float3 calculatePBRLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    float3 N = normalize(normal);
    float3 V = normalize(cameraPos - worldPos);

    float metallic = material.emissiveAndMetallic.w;
    float roughness = clamp(material.pbrParams.x, 0.04, 1.0);
    float ao = material.pbrParams.z;

    // 非金属は 0.04 の基本反射率、金属はベースカラーを使用
    float3 F0 = mix(float3(0.04), baseColor, metallic);

    float3 Lo = float3(0.0);

    for (uint i = 0; i < lightCount; i++) {
        float3 lightColor = lights[i].colorAndIntensity.xyz * lights[i].colorAndIntensity.w;
        uint lightType = uint(lights[i].positionAndType.w);

        float3 L;
        float attenuation = 1.0;

        if (lightType == 0) {
            // Directional light
            L = normalize(-lights[i].directionAndCutoff.xyz);
        } else {
            float3 lightVec = lights[i].positionAndType.xyz - worldPos;
            float dist = length(lightVec);
            L = lightVec / max(dist, 0.0001);

            float3 att = lights[i].attenuationAndOuterCutoff.xyz;
            attenuation = 1.0 / (att.x + att.y * dist + att.z * dist * dist);

            if (lightType == 2) {
                // Spot light
                float3 spotDir = normalize(lights[i].directionAndCutoff.xyz);
                float theta = dot(L, -spotDir);
                float innerCutoff = lights[i].directionAndCutoff.w;
                float outerCutoff = lights[i].attenuationAndOuterCutoff.w;
                float epsilon = innerCutoff - outerCutoff;
                float spotIntensity = clamp((theta - outerCutoff) / max(epsilon, 0.001), 0.0, 1.0);
                attenuation *= spotIntensity;
            }
        }

        float3 H = normalize(V + L);
        float NdotL = max(dot(N, L), 0.0);

        // Cook-Torrance BRDF
        float D = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        float3 numerator = D * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001;
        float3 specular = numerator / denominator;

        // エネルギー保存: kS + kD = 1
        float3 kS = F;
        float3 kD = (1.0 - kS) * (1.0 - metallic);

        Lo += (kD * baseColor / M_PI_F + specular) * lightColor * NdotL * attenuation;
    }

    // Ambient (簡易: IBL なしのフォールバック)
    float3 ambient = material.ambientColor.xyz * baseColor * ao;
    float3 emissive = material.emissiveAndMetallic.xyz;

    return ambient + emissive + Lo;
}

// Blinn-Phong ライティング（既存互換）
static inline float3 calculateBlinnPhongLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    float3 N = normalize(normal);
    float3 V = normalize(cameraPos - worldPos);

    float3 ambient = material.ambientColor.xyz * baseColor;
    float3 result = ambient + material.emissiveAndMetallic.xyz;

    float metallic = material.emissiveAndMetallic.w;
    float shininess = max(material.specularAndShininess.w, 1.0);
    float3 specColor = mix(material.specularAndShininess.xyz, baseColor, metallic);
    float3 diffColor = baseColor * (1.0 - metallic);

    for (uint i = 0; i < lightCount; i++) {
        float3 lightColor = lights[i].colorAndIntensity.xyz * lights[i].colorAndIntensity.w;
        uint lightType = uint(lights[i].positionAndType.w);

        float3 L;
        float attenuation = 1.0;

        if (lightType == 0) {
            L = normalize(-lights[i].directionAndCutoff.xyz);
        } else {
            float3 lightVec = lights[i].positionAndType.xyz - worldPos;
            float dist = length(lightVec);
            L = lightVec / max(dist, 0.0001);

            float3 att = lights[i].attenuationAndOuterCutoff.xyz;
            attenuation = 1.0 / (att.x + att.y * dist + att.z * dist * dist);

            if (lightType == 2) {
                float3 spotDir = normalize(lights[i].directionAndCutoff.xyz);
                float theta = dot(L, -spotDir);
                float innerCutoff = lights[i].directionAndCutoff.w;
                float outerCutoff = lights[i].attenuationAndOuterCutoff.w;
                float epsilon = innerCutoff - outerCutoff;
                float spotIntensity = clamp((theta - outerCutoff) / max(epsilon, 0.001), 0.0, 1.0);
                attenuation *= spotIntensity;
            }
        }

        float NdotL = max(dot(N, L), 0.0);
        float3 diffuse = diffColor * NdotL;

        float3 H = normalize(L + V);
        float NdotH = max(dot(N, H), 0.0);
        float spec = (NdotL > 0.0) ? pow(NdotH, shininess) : 0.0;
        float3 specular = specColor * spec;

        result += (diffuse + specular) * lightColor * attenuation;
    }

    return result;
}

// 統合エントリポイント: pbrParams.y で Blinn-Phong / PBR を自動切替
static inline float3 calculateLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    if (material.pbrParams.y > 0.5) {
        return calculatePBRLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material);
    }
    return calculateBlinnPhongLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material);
}

#endif
