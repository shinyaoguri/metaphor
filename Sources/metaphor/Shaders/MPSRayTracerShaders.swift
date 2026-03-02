/// MPS レイトレーシング用 Metal シェーダーソース
enum MPSRayTracerShaders {
    static let source = """
    #include <metal_stdlib>
    #include <metal_raytracing>
    using namespace metal;

    // MARK: - Structs

    struct Ray {
        packed_float3 origin;
        float minDistance;
        packed_float3 direction;
        float maxDistance;
    };

    struct Intersection {
        float distance;
        int primitiveIndex;
        float2 coordinates;  // barycentric
    };

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

    // MARK: - Ray Generation

    kernel void generatePrimaryRays(
        device Ray *rays [[buffer(0)]],
        constant RayTraceUniforms &uniforms [[buffer(1)]],
        uint2 tid [[thread_position_in_grid]]
    ) {
        if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

        uint index = tid.y * uniforms.width + tid.x;

        // NDC coordinates [-1, 1]
        float2 ndc = float2(
            (float(tid.x) + 0.5) / float(uniforms.width) * 2.0 - 1.0,
            1.0 - (float(tid.y) + 0.5) / float(uniforms.height) * 2.0
        );

        // Unproject through inverse matrices
        float4 clipPos = float4(ndc, -1.0, 1.0);
        float4 viewPos = uniforms.inverseProjection * clipPos;
        viewPos /= viewPos.w;

        float4 worldPos = uniforms.inverseView * viewPos;
        float3 origin = (uniforms.inverseView * float4(0, 0, 0, 1)).xyz;
        float3 direction = normalize(worldPos.xyz - origin);

        rays[index].origin = origin;
        rays[index].direction = direction;
        rays[index].minDistance = 0.001;
        rays[index].maxDistance = 1000.0;
    }

    // MARK: - Ambient Occlusion Shading

    kernel void shadeAmbientOcclusion(
        device Ray *rays [[buffer(0)]],
        device Intersection *intersections [[buffer(1)]],
        device packed_float3 *normals [[buffer(2)]],
        device Ray *shadowRays [[buffer(3)]],
        constant RayTraceUniforms &uniforms [[buffer(4)]],
        texture2d<float, access::read_write> output [[texture(0)]],
        uint2 tid [[thread_position_in_grid]]
    ) {
        if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

        uint index = tid.y * uniforms.width + tid.x;
        Intersection intersection = intersections[index];

        if (intersection.distance < 0) {
            // Miss - background
            output.write(float4(0.1, 0.1, 0.15, 1.0), tid);
            return;
        }

        // Compute hit point
        Ray ray = rays[index];
        float3 hitPoint = float3(ray.origin) + float3(ray.direction) * intersection.distance;
        float3 normal = float3(normals[intersection.primitiveIndex]);

        // Generate AO sample ray
        uint seed = index + uniforms.sampleIndex * uniforms.width * uniforms.height;
        float3 sampleDir = randomInHemisphere(normal, seed);

        shadowRays[index].origin = hitPoint + normal * 0.001;
        shadowRays[index].direction = sampleDir;
        shadowRays[index].minDistance = 0.001;
        shadowRays[index].maxDistance = uniforms.aoRadius;
    }

    // MARK: - AO Accumulation

    kernel void accumulateAO(
        device Intersection *intersections [[buffer(0)]],
        device Intersection *shadowIntersections [[buffer(1)]],
        constant RayTraceUniforms &uniforms [[buffer(2)]],
        texture2d<float, access::read_write> output [[texture(0)]],
        uint2 tid [[thread_position_in_grid]]
    ) {
        if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

        uint index = tid.y * uniforms.width + tid.x;

        // Primary ray missed
        if (intersections[index].distance < 0) return;

        // Read current accumulated value
        float4 current = output.read(tid);

        // Shadow intersection: occluded = dark, unoccluded = bright
        float ao = shadowIntersections[index].distance < 0 ? 1.0 : 0.0;

        // Running average
        float weight = 1.0 / float(uniforms.sampleIndex + 1);
        float newValue = mix(current.r, ao, weight);

        output.write(float4(newValue, newValue, newValue, 1.0), tid);
    }

    // MARK: - Simple Diffuse Shading (soft shadow)

    kernel void shadeDiffuse(
        device Ray *rays [[buffer(0)]],
        device Intersection *intersections [[buffer(1)]],
        device packed_float3 *normals [[buffer(2)]],
        constant RayTraceUniforms &uniforms [[buffer(3)]],
        texture2d<float, access::read_write> output [[texture(0)]],
        uint2 tid [[thread_position_in_grid]]
    ) {
        if (tid.x >= uniforms.width || tid.y >= uniforms.height) return;

        uint index = tid.y * uniforms.width + tid.x;
        Intersection intersection = intersections[index];

        if (intersection.distance < 0) {
            output.write(float4(0.1, 0.1, 0.15, 1.0), tid);
            return;
        }

        float3 normal = float3(normals[intersection.primitiveIndex]);

        // Simple hemisphere lighting
        float3 lightDir = normalize(float3(1, 2, 1));
        float diffuse = max(dot(normal, lightDir), 0.0);
        float ambient = 0.15;
        float lighting = ambient + diffuse * 0.85;

        output.write(float4(lighting, lighting, lighting, 1.0), tid);
    }
    """
}
