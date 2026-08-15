// このファイルは生成物です。手で編集しないでください。
//
// 生成元: Sources/MetaphorCore/Shaders/Metal/*.h
// 再生成: python3 scripts/generate-shader-sources.py
//
// 公開 API（`BuiltinShaders.canvas3DStructs` / `PostProcessShaders.commonStructs`
// など）とその doc コメントは `BuiltinShaders.swift` / `PostProcessShaders.swift`
// 側にあります。ここが持つのは中身だけです。

/// ``BuiltinShaders`` / ``PostProcessShaders`` が公開する MSL 前文の実体。
///
/// 組み込みシェーダーと同じ `Shaders/Metal/*.h` から生成されるので、ライティングの
/// 実装や構造体のレイアウトを直せばカスタムシェーダーへ配られる前文も一緒に
/// 動きます（#707 / #718）。
///
/// 各定数は `#ifndef` ガードで包まれています。前文は `createMaterial()` /
/// `createPostEffect()` が必ず前置するので、以前の作法どおり自分でも前置している
/// ソースでは前文が 2 回現れます。ガードが 2 回目を空にします（#713 / #718）。
///
/// 定数そのものは `#include <metal_stdlib>` と `using namespace metal;` を持ちません
/// （それらを足した完全な前文が ``BuiltinShaders/canvas3DPreamble`` や
/// ``PostProcessShaders/postProcessPreamble``）。
enum BuiltinShadersGenerated {

    /// 生成元: MetaphorCanvas2DTypes.h
    static let canvas2DStructs = #"""
#ifndef METAPHOR_PRELUDE_CANVAS2D_STRUCTS
#define METAPHOR_PRELUDE_CANVAS2D_STRUCTS

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

#endif
"""#

    /// 生成元: MetaphorCanvas3DTypes.h
    static let canvas3DStructs = #"""
#ifndef METAPHOR_PRELUDE_CANVAS3D_STRUCTS
#define METAPHOR_PRELUDE_CANVAS3D_STRUCTS

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
"""#

    /// 生成元: MetaphorLighting.h（MetaphorPBR.h / MetaphorToneMapping.h を推移的に含む）
    static let canvas3DLightingFn = #"""
#ifndef METAPHOR_PRELUDE_CANVAS3D_LIGHTING
#define METAPHOR_PRELUDE_CANVAS3D_LIGHTING

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


// このヘッダは関数だけを持つ（構造体は `MetaphorCanvas3DTypes.h`）。
// そのまま `BuiltinShaders.canvas3DLightingFn` としてユーザーのカスタムマテリアル
// シェーダーへ配られる（`scripts/generate-shader-sources.py` が生成）。

// マテリアルに設定されたトーンマッピングをライティング結果へ適用する。
//
// 適用は**公開エントリポイント 1 か所だけ**で行う（`calculateLighting` /
// `calculatePBRLighting` / `calculateBlinnPhongLighting`）。内部の `…Raw`
// 関数はトーンマップ前の値を返すので、どの入口から呼んでも二重に掛からない。
static inline float3 metaphorToneMapped(float3 lit, Material3D material) {
    return metaphorApplyToneMap(lit, material.toneMapParams.x, material.toneMapParams.y);
}

// ライトが 1 つも無いときに無照明パス（fill 色をそのまま出す）へ落とすか。
//
// Processing 互換で「`lights()` を呼ばなければ塗りつぶし色がそのまま出る」のが既定
// だが、環境（IBL）を設定した PBR マテリアルだけは例外で、ライトが無くても環境が
// 照らす（`environment(.studio)` の 1 行で金属が金属に見えるようにするため・#710）。
// Blinn-Phong は IBL の対象外なので従来どおり無照明パスへ落とす。
static inline bool metaphorSkipsLighting(Material3D material, uint lightCount) {
    if (lightCount > 0) return false;
    return !(material.toneMapParams.z > 0.0 && material.pbrParams.y > 0.5);
}

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

// PBR (Cook-Torrance GGX) ライティング（トーンマップ前の生の値）
//
// `shadow` はシャドウマップの可視率（1 = 完全に照らされる / 0 = 完全な影）。
// 影は**直接光（diffuse + specular）にのみ**掛かる。環境光（ambient）と自発光
// （emissive）は遮蔽物の裏にも残るため減衰させない（Issue #364）。
static inline float3 metaphorPBRLightingRaw(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow
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

    return ambient + emissive + Lo * shadow;
}

// PBR ライティング + IBL（トーンマップ前の生の値）。
//
// 直接光の計算は ``metaphorPBRLightingRaw`` をそのまま使い、環境の寄与だけを足す。
// IBL は環境光と同じく**影で減衰しない項**に入れる（``metaphorPBRLightingRaw`` の
// コメントにある Issue #364 の契約と一貫させる）。強度は
// `material.toneMapParams.z`（= `environment()` の intensity）で運ばれ、0 なら
// ``metaphorIBLContribution`` が 0 を返すので環境なしの絵は完全に不変。
static inline float3 metaphorPBRLightingRawIBL(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow,
    texturecube<float> irradianceMap,
    texturecube<float> prefilteredMap
) {
    float3 lit = metaphorPBRLightingRaw(
        worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow);

    float3 N = normalize(normal);
    float3 V = normalize(cameraPos - worldPos);
    lit += metaphorIBLContribution(
        N, V, baseColor,
        material.emissiveAndMetallic.w,
        clamp(material.pbrParams.x, 0.04, 1.0),
        material.pbrParams.z,
        material.toneMapParams.z,
        irradianceMap, prefilteredMap);

    return lit;
}

// Blinn-Phong ライティング（既存互換・トーンマップ前の生の値）
//
// `shadow` の意味は ``metaphorPBRLightingRaw`` と同じ（直接光にのみ掛かる）。
static inline float3 metaphorBlinnPhongLightingRaw(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow
) {
    float3 N = normalize(normal);
    float3 V = normalize(cameraPos - worldPos);

    float3 ambient = material.ambientColor.xyz * baseColor;
    // 影で減衰しない項（ambient + emissive）と、減衰する直接光を分けて積む。
    float3 direct = float3(0.0);

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

        direct += (diffuse + specular) * lightColor * attenuation;
    }

    return ambient + material.emissiveAndMetallic.xyz + direct * shadow;
}

// PBR (Cook-Torrance GGX) ライティング。結果にはトーンマッピングが適用される。
static inline float3 calculatePBRLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow
) {
    float3 lit = metaphorPBRLightingRaw(
        worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow);
    return metaphorToneMapped(lit, material);
}

// Blinn-Phong ライティング。結果にはトーンマッピングが適用される。
static inline float3 calculateBlinnPhongLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow
) {
    float3 lit = metaphorBlinnPhongLightingRaw(
        worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow);
    return metaphorToneMapped(lit, material);
}

// 統合エントリポイント: pbrParams.y で Blinn-Phong / PBR を自動切替
//
// トーンマッピングはここで 1 回だけ適用する（`…Raw` を呼んでから掛けるので、
// ``calculatePBRLighting`` 経由と二重に掛かることはない）。
static inline float3 calculateLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow
) {
    float3 lit = (material.pbrParams.y > 0.5)
        ? metaphorPBRLightingRaw(
            worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow)
        : metaphorBlinnPhongLightingRaw(
            worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow);
    return metaphorToneMapped(lit, material);
}

// 統合エントリポイント（IBL 付き）: 組み込み 3D フラグメントシェーダーが使う。
//
// キューブマップ 2 枚を追加で取るだけで、それ以外の意味は引数 8 個版と同じ。
// 環境が無効なとき（`toneMapParams.z == 0`）は 1x1 のダミーキューブがバインドされ、
// IBL の寄与は 0 になる。カスタムマテリアルシェーダーは従来どおり引数 8 個版を
// 呼べる（その場合 IBL は掛からない）。
static inline float3 calculateLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow,
    texturecube<float> irradianceMap,
    texturecube<float> prefilteredMap
) {
    float3 lit = (material.pbrParams.y > 0.5)
        ? metaphorPBRLightingRawIBL(
            worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow,
            irradianceMap, prefilteredMap)
        : metaphorBlinnPhongLightingRaw(
            worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow);
    return metaphorToneMapped(lit, material);
}

// PBR ライティング + IBL。結果にはトーンマッピングが適用される。
static inline float3 calculatePBRLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material,
    float shadow,
    texturecube<float> irradianceMap,
    texturecube<float> prefilteredMap
) {
    float3 lit = metaphorPBRLightingRawIBL(
        worldPos, normal, cameraPos, baseColor, lights, lightCount, material, shadow,
        irradianceMap, prefilteredMap);
    return metaphorToneMapped(lit, material);
}

// 影なし版（後方互換）。カスタムマテリアルシェーダーが従来のシグネチャで
// 呼んでいるため残す。
static inline float3 calculateLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    return calculateLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material, 1.0);
}

static inline float3 calculatePBRLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    return calculatePBRLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material, 1.0);
}

static inline float3 calculateBlinnPhongLighting(
    float3 worldPos,
    float3 normal,
    float3 cameraPos,
    float3 baseColor,
    constant Light3D *lights,
    uint lightCount,
    Material3D material
) {
    return calculateBlinnPhongLighting(worldPos, normal, cameraPos, baseColor, lights, lightCount, material, 1.0);
}

#endif
"""#

    /// 生成元: MetaphorPostProcessTypes.h
    static let postProcessStructs = #"""
#ifndef METAPHOR_PRELUDE_POSTPROCESS_STRUCTS
#define METAPHOR_PRELUDE_POSTPROCESS_STRUCTS

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
"""#
}
