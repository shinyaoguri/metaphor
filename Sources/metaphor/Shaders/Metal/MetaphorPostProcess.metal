#include <metal_stdlib>
using namespace metal;

struct PPVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

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

// MARK: - Invert

fragment float4 metaphor_postInvert(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.texCoord);
    return float4(1.0 - color.rgb, color.a);
}

// MARK: - Grayscale

fragment float4 metaphor_postGrayscale(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.texCoord);
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    return float4(float3(luma), color.a);
}

// MARK: - Vignette

fragment float4 metaphor_postVignette(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.texCoord);
    float2 uv = in.texCoord - 0.5;
    float dist = length(uv);
    float vig = smoothstep(params.intensity, params.intensity - params.smoothness, dist);
    return float4(color.rgb * vig, color.a);
}

// MARK: - Chromatic Aberration

fragment float4 metaphor_postChromaticAberration(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 dir = uv - 0.5;
    float r = tex.sample(s, uv + dir * params.intensity).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - dir * params.intensity).b;
    float a = tex.sample(s, uv).a;
    return float4(r, g, b, a);
}

// MARK: - Color Grading

fragment float4 metaphor_postColorGrade(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.texCoord);
    color.rgb += params.brightness;
    color.rgb = (color.rgb - 0.5) * params.contrast + 0.5;
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(float3(luma), color.rgb, params.saturation);
    color.r += params.temperature * 0.1;
    color.b -= params.temperature * 0.1;
    return float4(clamp(color.rgb, 0.0, 1.0), color.a);
}

// MARK: - Gaussian Blur (Horizontal)

fragment float4 metaphor_postBlurH(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    int r = int(params.radius);
    float sigma = params.radius * 0.5;
    float invSigma2 = 1.0 / (2.0 * sigma * sigma);
    for (int i = -r; i <= r; i++) {
        float weight = exp(-float(i * i) * invSigma2);
        float2 offset = float2(float(i) * params.texelSize.x, 0.0);
        result += tex.sample(s, in.texCoord + offset) * weight;
        totalWeight += weight;
    }
    return result / totalWeight;
}

// MARK: - Gaussian Blur (Vertical)

fragment float4 metaphor_postBlurV(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    int r = int(params.radius);
    float sigma = params.radius * 0.5;
    float invSigma2 = 1.0 / (2.0 * sigma * sigma);
    for (int i = -r; i <= r; i++) {
        float weight = exp(-float(i * i) * invSigma2);
        float2 offset = float2(0.0, float(i) * params.texelSize.y);
        result += tex.sample(s, in.texCoord + offset) * weight;
        totalWeight += weight;
    }
    return result / totalWeight;
}

// MARK: - Bloom Extract

fragment float4 metaphor_postBloomExtract(
    PPVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.texCoord);
    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float contribution = max(0.0, brightness - params.threshold) / max(brightness, 0.001);
    return float4(color.rgb * contribution, 1.0);
}

// MARK: - Bloom Composite

fragment float4 metaphor_postBloomComposite(
    PPVertexOut in [[stage_in]],
    texture2d<float> original [[texture(0)]],
    texture2d<float> bloomTex [[texture(1)]],
    constant PostProcessParams &params [[buffer(0)]]
) {
    constexpr sampler s(filter::linear);
    float4 base = original.sample(s, in.texCoord);
    float4 bloom = bloomTex.sample(s, in.texCoord);
    return float4(base.rgb + bloom.rgb * params.intensity, base.a);
}
