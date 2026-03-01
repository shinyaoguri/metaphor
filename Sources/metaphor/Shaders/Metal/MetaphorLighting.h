#ifndef MetaphorLighting_h
#define MetaphorLighting_h

#include "MetaphorShaderTypes.h"

static inline float3 calculateLighting(
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

#endif
