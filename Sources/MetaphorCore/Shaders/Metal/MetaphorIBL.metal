#include <metal_stdlib>
#include "MetaphorPBR.h"
using namespace metal;

// IBL（image-based lighting）のプリベイク。
//
// 3 段構成で、いずれも `IBLEnvironment.swift` から 1 プリセットにつき 1 回だけ実行される
// （毎フレームの compute フェーズには相乗りしない）:
//
// 1. `metaphor_iblBakeEnvironment` — プリセットの解析式から環境キューブを焼く
// 2. `metaphor_iblIrradiance`      — コサイン畳み込みで拡散用イラディアンスを作る
// 3. `metaphor_iblPrefilter`       — GGX 重点サンプリングで鏡面用の mip 連鎖を作る
//
// キューブへの書き込みは `.type2DArray` のテクスチャビュー経由で行う（スライス = 面）。
// サンプル数はすべて固定なので、同じ入力からは常に同じ結果になる（決定論）。

struct IBLBakeParams {
    uint size;          // 出力の一辺（ピクセル）
    uint preset;        // 0 = studio, 1 = sunset, 2 = overcast
    uint sampleCount;   // プリフィルタのサンプル数
    float roughness;    // プリフィルタ対象の粗さ
};

// MARK: - キューブ面 ⇄ 方向

// 面インデックスと [-1, 1] の面内座標から、サンプラーと同じ規約でワールド方向を作る。
static inline float3 metaphor_iblCubeDirection(uint face, float2 uv) {
    float u = uv.x;
    float v = uv.y;
    switch (face) {
        case 0:  return normalize(float3( 1.0, -v, -u));  // +X
        case 1:  return normalize(float3(-1.0, -v,  u));  // -X
        case 2:  return normalize(float3( u,  1.0,  v));  // +Y
        case 3:  return normalize(float3( u, -1.0, -v));  // -Y
        case 4:  return normalize(float3( u, -v,  1.0));  // +Z
        default: return normalize(float3(-u, -v, -1.0));  // -Z
    }
}

// MARK: - プリセットの解析式

// metaphor のワールドは Processing 由来で **+Y が画面下**（投影行列に flipY が入る）。
// したがって「上」は -Y。プリセットはすべてこの向きを前提に書く。
static inline float metaphor_iblUpness(float3 d) {
    return -d.y;
}

// studio: 天井の白いパネル 2 枚 + 中間グレーの壁 + 暗い床。
// Three.js の RoomEnvironment に対応する位置づけで、無彩色なので素材の質感を見るのに向く。
static inline float3 metaphor_iblStudio(float3 d) {
    float up = metaphor_iblUpness(d);

    // 壁 → 天井 → 床の下地
    float3 wall = float3(0.16, 0.16, 0.18);
    float3 ceiling = float3(0.32, 0.32, 0.34);
    float3 floorColor = float3(0.06, 0.06, 0.07);
    float3 base = mix(wall, ceiling, smoothstep(0.0, 0.75, up));
    base = mix(base, floorColor, smoothstep(0.0, -0.45, up));

    // 天井に貼った矩形パネル 2 枚（天井平面 y = -1 へ投影して矩形で切る）
    if (up > 0.15) {
        float px = d.x / up;
        float pz = d.z / up;
        float panel = 0.0;
        // 手前と奥に 1 枚ずつ
        float2 halfSize = float2(0.62, 1.35);
        float2 centers[2] = { float2(-0.85, 0.0), float2(0.85, 0.0) };
        for (uint i = 0; i < 2; i++) {
            float2 q = abs(float2(px, pz) - centers[i]);
            float inside = (1.0 - smoothstep(halfSize.x * 0.7, halfSize.x, q.x))
                         * (1.0 - smoothstep(halfSize.y * 0.7, halfSize.y, q.y));
            panel = max(panel, inside);
        }
        base += float3(4.0, 3.9, 3.7) * panel;
    }

    // 側面のソフトボックス（-X 側）。キーライトの向きを作って立体感を出す。
    float side = smoothstep(0.55, 0.95, -d.x) * smoothstep(-0.5, 0.35, up);
    base += float3(1.1, 1.08, 1.05) * side;

    return base;
}

// sunset: 地平線のオレンジから上空の青へのグラデーション + 太陽ディスク。
static inline float3 metaphor_iblSunset(float3 d) {
    float up = metaphor_iblUpness(d);

    float3 horizon = float3(1.35, 0.62, 0.28);
    float3 zenith = float3(0.10, 0.20, 0.48);
    float3 ground = float3(0.09, 0.06, 0.05);

    float t = pow(clamp(up, 0.0, 1.0), 0.45);
    float3 color = mix(horizon, zenith, t);
    color = mix(color, ground, smoothstep(0.0, -0.30, up));

    // 太陽（地平線のすぐ上）
    float3 sunDir = normalize(float3(0.58, -0.14, -0.80));
    float cosAngle = dot(d, sunDir);
    color += float3(28.0, 16.0, 7.0) * smoothstep(0.9975, 0.9992, cosAngle);
    color += float3(3.2, 1.6, 0.7) * pow(max(cosAngle, 0.0), 96.0);

    return color;
}

// overcast: 曇天の白いドーム。全方位から柔らかい光が来るので影の輪郭が出にくい。
static inline float3 metaphor_iblOvercast(float3 d) {
    float up = metaphor_iblUpness(d);

    float3 zenith = float3(1.45, 1.47, 1.55);
    float3 horizon = float3(0.48, 0.50, 0.56);
    float3 ground = float3(0.13, 0.13, 0.14);

    float3 color = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.6));
    color = mix(color, ground, smoothstep(0.05, -0.35, up));
    return color;
}

static inline float3 metaphor_iblPresetRadiance(float3 d, uint preset) {
    if (preset == 1) return metaphor_iblSunset(d);
    if (preset == 2) return metaphor_iblOvercast(d);
    return metaphor_iblStudio(d);
}

// MARK: - 1. 環境キューブのベイク

kernel void metaphor_iblBakeEnvironment(
    texture2d_array<float, access::write> outFaces [[texture(0)]],
    constant IBLBakeParams &params [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.size || gid.y >= params.size || gid.z >= 6) return;

    float2 uv = (float2(gid.xy) + 0.5) / float(params.size) * 2.0 - 1.0;
    float3 dir = metaphor_iblCubeDirection(gid.z, uv);
    float3 color = metaphor_iblPresetRadiance(dir, params.preset);

    outFaces.write(float4(color, 1.0), gid.xy, gid.z);
}

// MARK: - 2. イラディアンス（拡散）

kernel void metaphor_iblIrradiance(
    texturecube<float> envMap [[texture(0)]],
    texture2d_array<float, access::write> outFaces [[texture(1)]],
    constant IBLBakeParams &params [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.size || gid.y >= params.size || gid.z >= 6) return;

    constexpr sampler envSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float2 uv = (float2(gid.xy) + 0.5) / float(params.size) * 2.0 - 1.0;
    float3 N = metaphor_iblCubeDirection(gid.z, uv);

    // N を法線とする接空間
    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 right = normalize(cross(up, N));
    up = normalize(cross(N, right));

    float3 irradiance = float3(0.0);
    float sampleCount = 0.0;
    const float sampleDelta = 0.045;

    for (float phi = 0.0; phi < 2.0 * M_PI_F; phi += sampleDelta) {
        for (float theta = 0.0; theta < 0.5 * M_PI_F; theta += sampleDelta) {
            float sinTheta = sin(theta);
            float cosTheta = cos(theta);
            float3 tangentSample = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;
            // 低い mip を引いて、粗いサンプリング間隔でもバンディングが出ないようにする
            irradiance += envMap.sample(envSampler, sampleVec, level(2.0)).rgb * cosTheta * sinTheta;
            sampleCount += 1.0;
        }
    }

    irradiance = M_PI_F * irradiance / max(sampleCount, 1.0);
    outFaces.write(float4(irradiance, 1.0), gid.xy, gid.z);
}

// MARK: - 3. プリフィルタ（鏡面）

static inline float metaphor_radicalInverseVdC(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

static inline float2 metaphor_hammersley(uint i, uint n) {
    return float2(float(i) / float(n), metaphor_radicalInverseVdC(i));
}

static inline float3 metaphor_importanceSampleGGX(float2 xi, float3 N, float roughness) {
    float a = roughness * roughness;

    float phi = 2.0 * M_PI_F * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    float3 H = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangentX = normalize(cross(up, N));
    float3 tangentY = cross(N, tangentX);

    return normalize(tangentX * H.x + tangentY * H.y + N * H.z);
}

kernel void metaphor_iblPrefilter(
    texturecube<float> envMap [[texture(0)]],
    texture2d_array<float, access::write> outFaces [[texture(1)]],
    constant IBLBakeParams &params [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.size || gid.y >= params.size || gid.z >= 6) return;

    constexpr sampler envSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float2 uv = (float2(gid.xy) + 0.5) / float(params.size) * 2.0 - 1.0;
    float3 N = metaphor_iblCubeDirection(gid.z, uv);
    float3 R = N;
    float3 V = N;

    float roughness = params.roughness;
    if (roughness <= 0.0) {
        outFaces.write(float4(envMap.sample(envSampler, N, level(0.0)).rgb, 1.0), gid.xy, gid.z);
        return;
    }

    uint sampleCount = max(params.sampleCount, 1u);
    float envSize = float(max(envMap.get_width(), 1u));
    float saTexel = 4.0 * M_PI_F / (6.0 * envSize * envSize);

    float3 prefiltered = float3(0.0);
    float totalWeight = 0.0;

    for (uint i = 0; i < sampleCount; i++) {
        float2 xi = metaphor_hammersley(i, sampleCount);
        float3 H = metaphor_importanceSampleGGX(xi, N, roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = dot(N, L);
        if (NdotL <= 0.0) continue;

        // サンプル密度に応じて mip を選び、点サンプルによるちらつきを抑える
        float NdotH = max(dot(N, H), 0.0);
        float HdotV = max(dot(H, V), 0.0);
        float D = DistributionGGX(N, H, roughness);
        float pdf = (D * NdotH / (4.0 * HdotV)) + 0.0001;
        float saSample = 1.0 / (float(sampleCount) * pdf + 0.0001);
        float mipLevel = 0.5 * log2(saSample / saTexel);

        prefiltered += envMap.sample(envSampler, L, level(max(mipLevel, 0.0))).rgb * NdotL;
        totalWeight += NdotL;
    }

    prefiltered /= max(totalWeight, 0.001);
    outFaces.write(float4(prefiltered, 1.0), gid.xy, gid.z);
}
