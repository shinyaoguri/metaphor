#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

// MARK: - Structs

struct RayTraceUniforms {
    float4x4 inverseView;
    float4x4 inverseProjection;
    uint width;
    uint height;
    uint sampleIndex;
    uint totalSamples;
    float aoRadius;
    float shadowSoftness;
    int maxBounces;
    float padding;
};

// MARK: - Random

/// Hash-based RNG (PCG variant)
uint hashSeed(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed = seed ^ (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed = seed ^ (seed >> 15u);
    return seed;
}

float randomFloat(thread uint &seed) {
    seed = hashSeed(seed);
    return float(seed) / float(0xFFFFFFFFu);
}

float3 randomInHemisphere(float3 normal, thread uint &seed) {
    float u = randomFloat(seed);
    float v = randomFloat(seed);
    float phi = 2.0 * M_PI_F * u;
    float cosTheta = sqrt(1.0 - v);
    float sinTheta = sqrt(v);

    // Build tangent frame
    float3 up = abs(normal.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);

    return tangent * (cos(phi) * sinTheta)
         + bitangent * (sin(phi) * sinTheta)
         + normal * cosTheta;
}

// MARK: - Ray Generation Helper

/// Generate a primary ray from pixel coordinates and camera matrices.
ray generatePrimaryRay(uint2 tid, constant RayTraceUniforms &uniforms) {
    float2 ndc = float2(
        (float(tid.x) + 0.5) / float(uniforms.width) * 2.0 - 1.0,
        1.0 - (float(tid.y) + 0.5) / float(uniforms.height) * 2.0
    );

    float4 clipPos = float4(ndc, -1.0, 1.0);
    float4 viewPos = uniforms.inverseProjection * clipPos;
    viewPos /= viewPos.w;

    float4 worldPos = uniforms.inverseView * viewPos;
    float3 origin = (uniforms.inverseView * float4(0, 0, 0, 1)).xyz;
    float3 direction = normalize(worldPos.xyz - origin);

    ray r;
    r.origin = origin;
    r.direction = direction;
    r.min_distance = 0.001;
    r.max_distance = 1000.0;
    return r;
}

// MARK: - Ambient Occlusion (inline intersection)

kernel void traceAmbientOcclusion(
    primitive_acceleration_structure accel [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    constant RayTraceUniforms &uniforms [[buffer(2)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 tid [[thread_position_in_grid]]
) {
    if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

    uint pixelIndex = tid.y * uniforms.width + tid.x;

    // Primary ray
    ray primaryRay = generatePrimaryRay(tid, uniforms);

    intersector<triangle_data> primaryIntersector;
    primaryIntersector.accept_any_intersection(false);
    auto primaryHit = primaryIntersector.intersect(primaryRay, accel);

    if (primaryHit.type == intersection_type::none) {
        output.write(float4(0.1, 0.1, 0.15, 1.0), tid);
        return;
    }

    // Hit point and normal
    float3 hitPoint = primaryRay.origin + primaryRay.direction * primaryHit.distance;
    float3 normal = normals[primaryHit.primitive_id];

    // AO sampling loop
    intersector<triangle_data> shadowIntersector;
    shadowIntersector.accept_any_intersection(true);

    float aoAccum = 0.0;
    uint totalSamples = uniforms.totalSamples;

    for (uint s = 0; s < totalSamples; s++) {
        uint seed = pixelIndex + s * uniforms.width * uniforms.height;
        float3 sampleDir = randomInHemisphere(normal, seed);

        ray shadowRay;
        shadowRay.origin = hitPoint + normal * 0.001;
        shadowRay.direction = sampleDir;
        shadowRay.min_distance = 0.001;
        shadowRay.max_distance = uniforms.aoRadius;

        auto shadowHit = shadowIntersector.intersect(shadowRay, accel);
        aoAccum += (shadowHit.type == intersection_type::none) ? 1.0 : 0.0;
    }

    float ao = aoAccum / float(totalSamples);
    output.write(float4(ao, ao, ao, 1.0), tid);
}

// MARK: - Soft Shadow (inline intersection)

kernel void traceSoftShadow(
    primitive_acceleration_structure accel [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    constant RayTraceUniforms &uniforms [[buffer(2)]],
    constant float3 &lightDirection [[buffer(3)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 tid [[thread_position_in_grid]]
) {
    if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

    uint pixelIndex = tid.y * uniforms.width + tid.x;

    // Primary ray
    ray primaryRay = generatePrimaryRay(tid, uniforms);

    intersector<triangle_data> primaryIntersector;
    primaryIntersector.accept_any_intersection(false);
    auto primaryHit = primaryIntersector.intersect(primaryRay, accel);

    if (primaryHit.type == intersection_type::none) {
        output.write(float4(0.1, 0.1, 0.15, 1.0), tid);
        return;
    }

    float3 hitPoint = primaryRay.origin + primaryRay.direction * primaryHit.distance;
    float3 normal = normals[primaryHit.primitive_id];
    float3 lightDir = normalize(lightDirection);

    // Shadow sampling loop with jittered light direction
    intersector<triangle_data> shadowIntersector;
    shadowIntersector.accept_any_intersection(true);

    float shadowAccum = 0.0;
    uint totalSamples = uniforms.totalSamples;

    for (uint s = 0; s < totalSamples; s++) {
        uint seed = pixelIndex + s * uniforms.width * uniforms.height;

        // Jitter the light direction for soft shadows
        float3 jitter = float3(
            (randomFloat(seed) - 0.5) * uniforms.shadowSoftness,
            (randomFloat(seed) - 0.5) * uniforms.shadowSoftness,
            (randomFloat(seed) - 0.5) * uniforms.shadowSoftness
        );
        float3 jitteredDir = normalize(lightDir + jitter);

        ray shadowRay;
        shadowRay.origin = hitPoint + normal * 0.001;
        shadowRay.direction = jitteredDir;
        shadowRay.min_distance = 0.001;
        shadowRay.max_distance = 1000.0;

        auto shadowHit = shadowIntersector.intersect(shadowRay, accel);
        shadowAccum += (shadowHit.type == intersection_type::none) ? 1.0 : 0.0;
    }

    float shadow = shadowAccum / float(totalSamples);
    // Apply diffuse lighting with shadow
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.15;
    float lighting = ambient + diffuse * 0.85 * shadow;

    output.write(float4(lighting, lighting, lighting, 1.0), tid);
}

// MARK: - Diffuse Shading (inline intersection)

kernel void traceDiffuse(
    primitive_acceleration_structure accel [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    constant RayTraceUniforms &uniforms [[buffer(2)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 tid [[thread_position_in_grid]]
) {
    if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

    // Primary ray
    ray primaryRay = generatePrimaryRay(tid, uniforms);

    intersector<triangle_data> primaryIntersector;
    primaryIntersector.accept_any_intersection(false);
    auto primaryHit = primaryIntersector.intersect(primaryRay, accel);

    if (primaryHit.type == intersection_type::none) {
        output.write(float4(0.1, 0.1, 0.15, 1.0), tid);
        return;
    }

    float3 normal = normals[primaryHit.primitive_id];

    // Simple hemisphere lighting
    float3 lightDir = normalize(float3(1, 2, 1));
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.15;
    float lighting = ambient + diffuse * 0.85;

    output.write(float4(lighting, lighting, lighting, 1.0), tid);
}
