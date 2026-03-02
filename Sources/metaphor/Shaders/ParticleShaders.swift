import Foundation

/// GPU パーティクルシステム用 MSL シェーダーソース
enum ParticleShaders {

    /// シェーダー関数名
    enum FunctionName {
        static let update = "metaphor_particleUpdate"
        static let vertex = "metaphor_particleVertex"
        static let fragment = "metaphor_particleFragment"
        static let resetCounter = "metaphor_particleResetCounter"
        static let compact = "metaphor_particleCompact"
        static let buildIndirectArgs = "metaphor_particleBuildIndirectArgs"
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // ---- GPU Structs ----

    struct Particle {
        float4 position;      // xyz=pos, w=remainingLife
        float4 velocity;      // xyz=vel, w=age
        float4 color;         // rgba
        float4 sizeAndFlags;  // x=size, y=originalLife, z=unused, w=alive(1/0)
    };

    struct ForceDescriptor {
        float4 typeAndParams;      // x=type, yzw=params
        float4 strengthAndExtra;   // x=strength, yzw=extra
    };

    struct ParticleUniforms {
        float deltaTime;
        float time;
        uint  particleCount;
        uint  forceCount;
        float emissionRate;
        float particleLife;
        float particleSize;
        float _pad;
        float4 startColor;
        float4 endColor;
        uint  emitterType;   // 0=point, 1=line, 2=circle, 3=sphere
        uint  _pad2;
        uint  _pad3;
        uint  _pad4;
        float4 emitterParam1;
        float4 emitterParam2;
    };

    struct ParticleRenderUniforms {
        float4x4 viewProjection;
        float4 cameraRight;   // xyz used
        float4 cameraUp;      // xyz used
    };

    // ---- Noise Helpers ----

    float metaphor_hash(float n) {
        return fract(sin(n) * 43758.5453123);
    }

    float metaphor_noise3d(float3 p) {
        float3 i = floor(p);
        float3 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float n = i.x + i.y * 57.0 + i.z * 113.0;
        return mix(
            mix(mix(metaphor_hash(n),        metaphor_hash(n + 1.0),   f.x),
                mix(metaphor_hash(n + 57.0), metaphor_hash(n + 58.0),  f.x), f.y),
            mix(mix(metaphor_hash(n + 113.0), metaphor_hash(n + 114.0), f.x),
                mix(metaphor_hash(n + 170.0), metaphor_hash(n + 171.0), f.x), f.y),
            f.z
        );
    }

    // ---- Random ----

    float metaphor_rand(uint seed, uint offset) {
        uint h = seed * 1103515245u + 12345u + offset * 1999u;
        h = (h >> 16u) ^ h;
        h *= 0x45d9f3bu;
        h = (h >> 16u) ^ h;
        return float(h & 0xFFFFFFu) / float(0xFFFFFFu);
    }

    // ---- Compute: Particle Update ----

    kernel void metaphor_particleUpdate(
        device Particle *particlesIn  [[buffer(0)]],
        device Particle *particlesOut [[buffer(1)]],
        constant ParticleUniforms &uniforms [[buffer(2)]],
        constant ForceDescriptor *forces [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= uniforms.particleCount) return;

        Particle p = particlesIn[gid];
        float dt = uniforms.deltaTime;

        // ---- Dead particle: check if should respawn ----
        if (p.sizeAndFlags.w < 0.5) {
            float emitChance = uniforms.emissionRate * dt / float(uniforms.particleCount);
            uint timeSeed = uint(uniforms.time * 1000.0);
            float r = metaphor_rand(gid, timeSeed);

            if (r < emitChance) {
                float r1 = metaphor_rand(gid, timeSeed + 1u);
                float r2 = metaphor_rand(gid, timeSeed + 2u);
                float r3 = metaphor_rand(gid, timeSeed + 3u);

                float3 spawnPos;
                if (uniforms.emitterType == 0u) {
                    // Point
                    spawnPos = uniforms.emitterParam1.xyz;
                } else if (uniforms.emitterType == 1u) {
                    // Line
                    spawnPos = mix(uniforms.emitterParam1.xyz, uniforms.emitterParam2.xyz, r1);
                } else if (uniforms.emitterType == 2u) {
                    // Circle
                    float angle = r1 * 2.0 * M_PI_F;
                    float radius = uniforms.emitterParam2.x;
                    spawnPos = uniforms.emitterParam1.xyz
                        + float3(cos(angle) * radius, sin(angle) * radius, 0.0);
                } else {
                    // Sphere
                    float theta = r1 * 2.0 * M_PI_F;
                    float phi = acos(2.0 * r2 - 1.0);
                    float radius = uniforms.emitterParam2.x * pow(r3, 1.0 / 3.0);
                    spawnPos = uniforms.emitterParam1.xyz
                        + radius * float3(sin(phi) * cos(theta),
                                          sin(phi) * sin(theta),
                                          cos(phi));
                }

                // Random initial velocity (small spread)
                float vr1 = metaphor_rand(gid, timeSeed + 4u);
                float vr2 = metaphor_rand(gid, timeSeed + 5u);
                float vr3 = metaphor_rand(gid, timeSeed + 6u);

                p.position = float4(spawnPos, uniforms.particleLife);
                p.velocity = float4((vr1 - 0.5) * 0.5,
                                    (vr2 - 0.5) * 0.5,
                                    (vr3 - 0.5) * 0.5, 0.0);
                p.color = uniforms.startColor;
                p.sizeAndFlags = float4(uniforms.particleSize, uniforms.particleLife, 0.0, 1.0);
            }

            particlesOut[gid] = p;
            return;
        }

        // ---- Live particle: apply forces ----
        float3 acceleration = float3(0.0);

        for (uint i = 0; i < uniforms.forceCount; i++) {
            uint forceType = uint(forces[i].typeAndParams.x);
            float strength = forces[i].strengthAndExtra.x;

            if (forceType == 0u) {
                // Gravity: yzw = direction vector (already includes magnitude)
                acceleration += forces[i].typeAndParams.yzw * strength;
            } else if (forceType == 1u) {
                // Attraction
                float3 target = forces[i].typeAndParams.yzw;
                float3 dir = target - p.position.xyz;
                float dist = max(length(dir), 0.01);
                acceleration += normalize(dir) * strength / (dist * dist + 1.0);
            } else if (forceType == 2u) {
                // Repulsion
                float3 target = forces[i].typeAndParams.yzw;
                float3 dir = p.position.xyz - target;
                float dist = max(length(dir), 0.01);
                acceleration += normalize(dir) * strength / (dist * dist + 1.0);
            } else if (forceType == 3u) {
                // Noise
                float scale = forces[i].strengthAndExtra.y;
                float3 noisePos = p.position.xyz * scale + float3(uniforms.time * 0.5);
                float nx = metaphor_noise3d(noisePos) * 2.0 - 1.0;
                float ny = metaphor_noise3d(noisePos + float3(31.4, 0.0, 0.0)) * 2.0 - 1.0;
                float nz = metaphor_noise3d(noisePos + float3(0.0, 47.2, 0.0)) * 2.0 - 1.0;
                acceleration += float3(nx, ny, nz) * strength;
            } else if (forceType == 4u) {
                // Vortex: Y軸周りの回転力（yzw = 渦の中心座標）
                float3 center = forces[i].typeAndParams.yzw;
                float3 toParticle = p.position.xyz - center;
                // XZ平面での接線方向（Y軸回転）
                float3 tangent = float3(-toParticle.z, 0.0, toParticle.x);
                float tLen = length(tangent);
                if (tLen > 0.001) {
                    tangent /= tLen;
                }
                acceleration += tangent * strength;
            } else if (forceType == 5u) {
                // Damping
                p.velocity.xyz *= (1.0 - strength * dt);
            }
        }

        // Integrate
        p.velocity.xyz += acceleration * dt;
        p.position.xyz += p.velocity.xyz * dt;

        // Age
        p.velocity.w += dt;    // elapsed age
        p.position.w -= dt;    // remaining life

        // Color interpolation based on life ratio
        float lifeRatio = clamp(p.velocity.w / p.sizeAndFlags.y, 0.0, 1.0);
        p.color = mix(uniforms.startColor, uniforms.endColor, lifeRatio);

        // Kill if expired
        if (p.position.w <= 0.0) {
            p.sizeAndFlags.w = 0.0;
        }

        particlesOut[gid] = p;
    }

    // ---- Vertex: Billboard Quad ----

    struct ParticleVertexOut {
        float4 position [[position]];
        float4 color;
        float2 uv;
    };

    vertex ParticleVertexOut metaphor_particleVertex(
        uint vertexID   [[vertex_id]],
        uint instanceID [[instance_id]],
        device const Particle *particles [[buffer(0)]],
        constant ParticleRenderUniforms &uniforms [[buffer(1)]]
    ) {
        ParticleVertexOut out;
        Particle p = particles[instanceID];

        // Dead particles: degenerate off-screen
        if (p.sizeAndFlags.w < 0.5) {
            out.position = float4(0.0, 0.0, 2.0, 1.0);
            out.color = float4(0.0);
            out.uv = float2(0.0);
            return out;
        }

        // Quad corners (triangle strip): BL, BR, TL, TR
        float2 corners[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };

        float2 corner = corners[vertexID];
        float size = p.sizeAndFlags.x;

        // Billboard in world space
        float3 worldPos = p.position.xyz
            + uniforms.cameraRight.xyz * corner.x * size
            + uniforms.cameraUp.xyz    * corner.y * size;

        out.position = uniforms.viewProjection * float4(worldPos, 1.0);
        out.color = p.color;
        out.uv = corner * 0.5 + 0.5;

        return out;
    }

    // ---- Fragment: Soft Circle ----

    fragment float4 metaphor_particleFragment(
        ParticleVertexOut in [[stage_in]]
    ) {
        float dist = length(in.uv - float2(0.5)) * 2.0;
        float alpha = 1.0 - smoothstep(0.7, 1.0, dist);
        return float4(in.color.rgb, in.color.a * alpha);
    }

    // ---- Indirect Draw: Counter Reset ----

    kernel void metaphor_particleResetCounter(
        device atomic_uint *counter [[buffer(0)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid == 0) {
            atomic_store_explicit(counter, 0, memory_order_relaxed);
        }
    }

    // ---- Indirect Draw: Compact alive particles ----

    kernel void metaphor_particleCompact(
        device const Particle *particlesIn [[buffer(0)]],
        device Particle *particlesOut [[buffer(1)]],
        device atomic_uint *counter [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        Particle p = particlesIn[gid];
        if (p.sizeAndFlags.w >= 0.5) {
            uint idx = atomic_fetch_add_explicit(counter, 1, memory_order_relaxed);
            particlesOut[idx] = p;
        }
    }

    // ---- Indirect Draw: Build indirect arguments ----

    struct MTLDrawPrimitivesIndirectArguments_s {
        uint vertexCount;
        uint instanceCount;
        uint vertexStart;
        uint baseInstance;
    };

    kernel void metaphor_particleBuildIndirectArgs(
        device atomic_uint *counter [[buffer(0)]],
        device MTLDrawPrimitivesIndirectArguments_s *args [[buffer(1)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid == 0) {
            args->vertexCount = 4;
            args->instanceCount = atomic_load_explicit(counter, memory_order_relaxed);
            args->vertexStart = 0;
            args->baseInstance = 0;
        }
    }
    """
}
