import metaphor

struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var life: Float
    var size: Float
}

final class ParticleSystem {
    private let device: MTLDevice
    private var computePipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!
    private var particleBuffer: MTLBuffer!
    private let maxParticles: Int
    private var lastTime: Double = 0

    init(device: MTLDevice, maxParticles: Int = 50000) {
        self.device = device
        self.maxParticles = maxParticles
        buildComputePipeline()
        buildRenderPipeline()
        initializeParticles()
    }

    private func buildComputePipeline() {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct Particle {
            float2 position;
            float2 velocity;
            float4 color;
            float life;
            float size;
        };

        // Simple hash function for randomness
        float hash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        kernel void updateParticles(
            device Particle *particles [[buffer(0)]],
            constant float &time [[buffer(1)]],
            constant float &deltaTime [[buffer(2)]],
            uint id [[thread_position_in_grid]]
        ) {
            Particle p = particles[id];

            // Update life
            p.life -= deltaTime * 0.3;

            if (p.life <= 0) {
                // Respawn particle
                float angle = hash(float2(float(id), time)) * 2.0 * M_PI_F;
                float speed = hash(float2(time, float(id))) * 0.5 + 0.2;

                p.position = float2(0, 0);
                p.velocity = float2(cos(angle), sin(angle)) * speed;
                p.life = hash(float2(float(id) * 0.1, time * 0.1)) * 0.8 + 0.2;
                p.size = hash(float2(time * 0.5, float(id) * 0.5)) * 4.0 + 2.0;

                // Rainbow colors based on angle
                float hue = angle / (2.0 * M_PI_F);
                float3 rgb = abs(fract(hue + float3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0;
                rgb = clamp(rgb, 0.0, 1.0);
                p.color = float4(rgb, 1.0);
            }

            // Apply forces
            float2 center = float2(0, 0);
            float2 toCenter = center - p.position;
            float dist = length(toCenter);

            // Slight attraction to center
            if (dist > 0.01) {
                p.velocity += normalize(toCenter) * deltaTime * 0.05;
            }

            // Swirl effect
            float2 tangent = float2(-toCenter.y, toCenter.x);
            p.velocity += tangent * deltaTime * 0.1;

            // Damping
            p.velocity *= 0.995;

            // Update position
            p.position += p.velocity * deltaTime;

            // Fade out
            p.color.a = p.life;

            particles[id] = p;
        }
        """

        let library = try! device.makeLibrary(source: source, options: nil)
        let function = library.makeFunction(name: "updateParticles")!
        computePipeline = try! device.makeComputePipelineState(function: function)
    }

    private func buildRenderPipeline() {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct Particle {
            float2 position;
            float2 velocity;
            float4 color;
            float life;
            float size;
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
            float pointSize [[point_size]];
        };

        vertex VertexOut particleVertex(
            const device Particle *particles [[buffer(0)]],
            uint vertexID [[vertex_id]]
        ) {
            Particle p = particles[vertexID];

            VertexOut out;
            out.position = float4(p.position, 0, 1);
            out.color = p.color;
            out.pointSize = p.size;
            return out;
        }

        fragment float4 particleFragment(
            VertexOut in [[stage_in]],
            float2 pointCoord [[point_coord]]
        ) {
            // Soft circle
            float dist = length(pointCoord - 0.5) * 2.0;
            float alpha = 1.0 - smoothstep(0.0, 1.0, dist);

            return float4(in.color.rgb, in.color.a * alpha);
        }
        """

        let library = try! device.makeLibrary(source: source, options: nil)
        let vertexFunction = library.makeFunction(name: "particleVertex")
        let fragmentFunction = library.makeFunction(name: "particleFragment")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        // Additive blending
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        renderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func initializeParticles() {
        var particles = [Particle]()
        particles.reserveCapacity(maxParticles)

        for _ in 0..<maxParticles {
            let angle = Float.random(in: 0...(2 * .pi))
            let speed = Float.random(in: 0.1...0.5)

            let particle = Particle(
                position: SIMD2<Float>(0, 0),
                velocity: SIMD2<Float>(cos(angle), sin(angle)) * speed,
                color: SIMD4<Float>(1, 1, 1, 1),
                life: Float.random(in: 0...1),
                size: Float.random(in: 2...6)
            )
            particles.append(particle)
        }

        particleBuffer = device.makeBuffer(
            bytes: particles,
            length: MemoryLayout<Particle>.stride * maxParticles,
            options: .storageModeShared
        )
    }

    func update(time: Double) {
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let deltaTime = lastTime == 0 ? 0.016 : Float(time - lastTime)
        lastTime = time

        var timeFloat = Float(time)
        var delta = deltaTime

        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&timeFloat, length: MemoryLayout<Float>.size, index: 1)
        encoder.setBytes(&delta, length: MemoryLayout<Float>.size, index: 2)

        let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (maxParticles + 255) / 256,
            height: 1,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: maxParticles)
    }
}
