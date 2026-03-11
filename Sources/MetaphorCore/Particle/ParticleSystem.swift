@preconcurrency import Metal
import simd

// MARK: - Particle (GPU Compatible, 64 bytes)

/// Represent a single GPU-compatible particle (64 bytes, 16-byte aligned).
///
/// This struct is shared between Swift and MSL and must maintain exact
/// layout compatibility with the Metal shader counterpart.
public struct Particle {
    /// The position (xyz) and remaining lifetime (w).
    public var position: SIMD4<Float>

    /// The velocity (xyz) and elapsed time (w).
    public var velocity: SIMD4<Float>

    /// The RGBA color of the particle.
    public var color: SIMD4<Float>

    /// Packed fields: x = size, y = initial lifetime, z = unused, w = alive flag (1.0 or 0.0).
    public var sizeAndFlags: SIMD4<Float>

    /// Create a zeroed-out particle (dead by default).
    public init() {
        position = .zero
        velocity = .zero
        color = .zero
        sizeAndFlags = .zero
    }
}

// MARK: - Particle Force

/// Define a force type that can be applied to particles each frame.
public enum ParticleForce {
    /// Constant gravitational acceleration in the given direction.
    case gravity(Float, Float, Float)

    /// Attraction toward a point with the given strength.
    case attraction(x: Float, y: Float, z: Float, strength: Float)

    /// Repulsion away from a point with the given strength.
    case repulsion(x: Float, y: Float, z: Float, strength: Float)

    /// Noise-based force with configurable scale and strength.
    case noise(scale: Float, strength: Float)

    /// Vortex force rotating around an axis with the given strength.
    case vortex(x: Float, y: Float, z: Float, strength: Float)

    /// Velocity damping that decays speed each frame by the given factor.
    case damping(Float)
}

// MARK: - Emitter Shape

/// Define the spatial shape from which particles are emitted.
public enum EmitterShape {
    /// Emit from a single point.
    case point(Float, Float, Float)

    /// Emit along a line segment between two endpoints.
    case line(x1: Float, y1: Float, z1: Float, x2: Float, y2: Float, z2: Float)

    /// Emit from a circle on the XY plane.
    case circle(x: Float, y: Float, z: Float, radius: Float)

    /// Emit from the surface of a sphere.
    case sphere(x: Float, y: Float, z: Float, radius: Float)
}

// MARK: - GPU Structs (Swift <-> MSL matching)

/// Describe a force for the GPU compute shader (32 bytes).
///
/// - `typeAndParams`: x = force type index, yzw = position or direction parameters.
/// - `strengthAndExtra`: x = strength, yzw = extra parameters (e.g. noise scale).
struct ForceDescriptor {
    var typeAndParams: SIMD4<Float>       // x=type, yzw=params
    var strengthAndExtra: SIMD4<Float>    // x=strength, yzw=extra
}

/// Hold per-frame uniform data for the particle update compute shader.
struct ParticleUniforms {
    var deltaTime: Float
    var time: Float
    var particleCount: UInt32
    var forceCount: UInt32
    var emissionRate: Float
    var particleLife: Float
    var particleSize: Float
    var _pad: Float = 0
    var startColor: SIMD4<Float>
    var endColor: SIMD4<Float>
    var emitterType: UInt32
    var _pad2: UInt32 = 0
    var _pad3: UInt32 = 0
    var _pad4: UInt32 = 0
    var emitterParam1: SIMD4<Float>
    var emitterParam2: SIMD4<Float>
}

/// Hold per-frame uniform data for the particle render vertex shader (96 bytes).
struct ParticleRenderUniforms {
    var viewProjection: float4x4
    var cameraRight: SIMD4<Float>    // xyz used
    var cameraUp: SIMD4<Float>       // xyz used
}

// MARK: - ParticleSystem

/// Drive a GPU-based particle system using Metal compute shaders.
///
/// ``ParticleSystem`` double-buffers particle data and updates all particles
/// in parallel on the GPU each frame. Rendering uses instanced billboard quads
/// with additive blending.
///
/// ```swift
/// let ps = try createParticleSystem(count: 100_000)
/// ps.setEmitter(.sphere(x: 0, y: 0, z: 0, radius: 1.0))
/// ps.addForce(.gravity(0, -9.8, 0))
/// // In compute(): updateParticles(ps)
/// // In draw(): drawParticles(ps)
/// ```
@MainActor
public final class ParticleSystem {
    /// The maximum number of particles in this system.
    public let count: Int

    // MARK: - Emitter Settings

    /// The shape from which new particles are emitted.
    public var emitter: EmitterShape = .point(0, 0, 0)

    /// The emission rate in particles per second.
    public var emissionRate: Float = 10000

    /// The lifetime of each particle in seconds.
    public var particleLife: Float = 2.0

    /// The size of each particle in world units.
    public var particleSize: Float = 0.05

    /// The color of newly emitted particles.
    public var startColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// The color particles interpolate toward at the end of their lifetime.
    public var endColor: SIMD4<Float> = SIMD4(1, 1, 1, 0)

    // MARK: - Forces

    /// The list of forces currently applied to the system.
    public private(set) var forces: [ParticleForce] = []

    // MARK: - Metal Resources

    /// The Metal device used for buffer and pipeline creation.
    private let device: MTLDevice

    /// The first particle buffer (double-buffering: source or destination).
    private var bufferA: MTLBuffer

    /// The second particle buffer (double-buffering: source or destination).
    private var bufferB: MTLBuffer

    /// Toggle indicating which buffer is the current source.
    private var useBufferA = true

    /// The GPU buffer containing force descriptors, or nil if no forces are active.
    private var forceBuffer: MTLBuffer?

    /// The compute pipeline state for the particle update kernel.
    private let updatePipeline: MTLComputePipelineState

    /// The render pipeline state for drawing billboard quads.
    private let renderPipeline: MTLRenderPipelineState

    /// The depth stencil state (depth test enabled, write disabled).
    private let depthState: MTLDepthStencilState?

    // MARK: - Indirect Draw Resources

    /// Enable indirect draw to render only alive particles (defaults to `false` for backward compatibility).
    public var useIndirectDraw: Bool = false

    /// The buffer holding compacted alive particles for indirect draw.
    private var compactBuffer: MTLBuffer?

    /// The atomic counter buffer (4 bytes) for compaction.
    private var counterBuffer: MTLBuffer?

    /// The indirect arguments buffer (16 bytes) for `drawPrimitives(indirectBuffer:)`.
    private var indirectArgsBuffer: MTLBuffer?

    /// The compute pipeline for resetting the atomic counter.
    private let resetCounterPipeline: MTLComputePipelineState?

    /// The compute pipeline for compacting alive particles.
    private let compactPipeline: MTLComputePipelineState?

    /// The compute pipeline for building indirect draw arguments.
    private let buildArgsPipeline: MTLComputePipelineState?

    // MARK: - Initialization

    /// Create a new particle system with the specified capacity.
    ///
    /// - Parameters:
    ///   - device: The Metal device for resource creation.
    ///   - shaderLibrary: The shader library containing particle shader functions.
    ///   - sampleCount: The MSAA sample count for the render pipeline.
    ///   - count: The maximum number of particles.
    /// - Throws: ``MetaphorError/particle(_:)`` if GPU buffers cannot be
    ///   allocated, or if required shader
    ///   functions are missing.
    init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        sampleCount: Int,
        count: Int
    ) throws {
        self.device = device
        self.count = count

        // Double-buffered particle data
        let bufferSize = MemoryLayout<Particle>.stride * count
        guard let a = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let b = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw MetaphorError.particle(.bufferCreationFailed)
        }
        self.bufferA = a
        self.bufferB = b
        a.label = "metaphor.particle.bufferA"
        b.label = "metaphor.particle.bufferB"
        memset(a.contents(), 0, bufferSize)
        memset(b.contents(), 0, bufferSize)

        // Compute pipeline for particle update
        guard let updateFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.update,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw MetaphorError.particle(.shaderNotFound(ParticleShaders.FunctionName.update))
        }
        self.updatePipeline = try device.makeComputePipelineState(function: updateFn)

        // Render pipeline (no vertex descriptor: reads directly from buffer)
        guard let vertexFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.vertex,
            from: ShaderLibrary.BuiltinKey.particle
        ),
              let fragmentFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.fragment,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw MetaphorError.particle(.shaderNotFound("particle vertex/fragment"))
        }

        self.renderPipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .blending(.additive)
            .sampleCount(sampleCount)
            .build()

        // Depth stencil state (test enabled, write disabled for additive blending)
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = false
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)

        // Indirect draw pipelines (optional: falls back to normal mode on failure)
        if let resetFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.resetCounter,
            from: ShaderLibrary.BuiltinKey.particle
        ),
           let compactFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.compact,
            from: ShaderLibrary.BuiltinKey.particle
        ),
           let buildArgsFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.buildIndirectArgs,
            from: ShaderLibrary.BuiltinKey.particle
        ) {
            self.resetCounterPipeline = {
                do { return try device.makeComputePipelineState(function: resetFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (resetCounter): \(error)"); return nil }
            }()
            self.compactPipeline = {
                do { return try device.makeComputePipelineState(function: compactFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (compact): \(error)"); return nil }
            }()
            self.buildArgsPipeline = {
                do { return try device.makeComputePipelineState(function: buildArgsFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (buildArgs): \(error)"); return nil }
            }()

            // Compact buffer for alive particles
            self.compactBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
            self.compactBuffer?.label = "metaphor.particle.compact"
            // Atomic counter buffer (4 bytes)
            self.counterBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            self.counterBuffer?.label = "metaphor.particle.counter"
            // Indirect arguments buffer (16 bytes)
            self.indirectArgsBuffer = device.makeBuffer(
                length: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.size,
                options: .storageModeShared
            )
            self.indirectArgsBuffer?.label = "metaphor.particle.indirectArgs"
        } else {
            self.resetCounterPipeline = nil
            self.compactPipeline = nil
            self.buildArgsPipeline = nil
        }
    }

    // MARK: - Force Management

    /// Add a force to the particle system.
    ///
    /// - Parameter force: The force to add.
    public func addForce(_ force: ParticleForce) {
        forces.append(force)
        rebuildForceBuffer()
    }

    /// Remove all forces from the particle system.
    public func clearForces() {
        forces.removeAll()
        forceBuffer = nil
    }

    /// Set the emitter shape for particle spawning.
    ///
    /// - Parameter shape: The new emitter shape.
    public func setEmitter(_ shape: EmitterShape) {
        self.emitter = shape
    }

    // MARK: - Update (Compute Phase)

    /// Dispatch the particle update compute kernel.
    ///
    /// Call this during the compute phase of the frame. The kernel reads from
    /// the current source buffer, writes updated particles to the destination
    /// buffer, and swaps them for the next frame.
    ///
    /// - Parameters:
    ///   - encoder: The compute command encoder.
    ///   - deltaTime: The time since the last frame in seconds.
    ///   - time: The total elapsed time in seconds.
    func update(encoder: MTLComputeCommandEncoder, deltaTime: Float, time: Float) {
        let src = useBufferA ? bufferA : bufferB
        let dst = useBufferA ? bufferB : bufferA

        var uniforms = makeUniforms(deltaTime: deltaTime, time: time)

        encoder.setComputePipelineState(updatePipeline)
        encoder.setBuffer(src, offset: 0, index: 0)
        encoder.setBuffer(dst, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.size, index: 2)

        if let fb = forceBuffer {
            encoder.setBuffer(fb, offset: 0, index: 3)
        }

        let w = updatePipeline.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)

        useBufferA.toggle()

        // Indirect draw: compact alive particles
        if useIndirectDraw {
            compactAliveParticles(encoder: encoder)
        }
    }

    /// Compact alive particles into a contiguous buffer and build indirect draw arguments.
    private func compactAliveParticles(encoder: MTLComputeCommandEncoder) {
        guard let resetPipeline = resetCounterPipeline,
              let compactPipe = compactPipeline,
              let buildPipe = buildArgsPipeline,
              let compactBuf = compactBuffer,
              let counterBuf = counterBuffer,
              let argsBuf = indirectArgsBuffer else { return }

        let currentBuffer = useBufferA ? bufferA : bufferB

        // 1) Reset the atomic counter
        encoder.setComputePipelineState(resetPipeline)
        encoder.setBuffer(counterBuf, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))

        encoder.memoryBarrier(scope: .buffers)

        // 2) Compact alive particles into the compact buffer
        encoder.setComputePipelineState(compactPipe)
        encoder.setBuffer(currentBuffer, offset: 0, index: 0)
        encoder.setBuffer(compactBuf, offset: 0, index: 1)
        encoder.setBuffer(counterBuf, offset: 0, index: 2)
        let w = compactPipe.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))

        encoder.memoryBarrier(scope: .buffers)

        // 3) Build indirect draw arguments from the counter
        encoder.setComputePipelineState(buildPipe)
        encoder.setBuffer(counterBuf, offset: 0, index: 0)
        encoder.setBuffer(argsBuf, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    }

    // MARK: - Draw (Render Phase)

    /// Render the particles as instanced billboard quads.
    ///
    /// Call this during the render phase of the frame. Each alive particle is
    /// drawn as a camera-facing quad with additive blending.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder.
    ///   - viewProjection: The combined view-projection matrix.
    ///   - cameraRight: The camera's right direction vector (for billboard orientation).
    ///   - cameraUp: The camera's up direction vector (for billboard orientation).
    func draw(
        encoder: MTLRenderCommandEncoder,
        viewProjection: float4x4,
        cameraRight: SIMD3<Float>,
        cameraUp: SIMD3<Float>
    ) {
        var renderUniforms = ParticleRenderUniforms(
            viewProjection: viewProjection,
            cameraRight: SIMD4(cameraRight.x, cameraRight.y, cameraRight.z, 0),
            cameraUp: SIMD4(cameraUp.x, cameraUp.y, cameraUp.z, 0)
        )

        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBytes(&renderUniforms, length: MemoryLayout<ParticleRenderUniforms>.size, index: 1)

        if useIndirectDraw,
           let compactBuf = compactBuffer,
           let argsBuf = indirectArgsBuffer {
            // Indirect draw: render only compacted alive particles
            encoder.setVertexBuffer(compactBuf, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                indirectBuffer: argsBuf,
                indirectBufferOffset: 0
            )
        } else {
            // Standard draw: instanced rendering of all particle slots
            let currentBuffer = useBufferA ? bufferA : bufferB
            encoder.setVertexBuffer(currentBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: count
            )
        }
    }

    // MARK: - Private Helpers

    /// Build the uniform struct for the particle update compute kernel.
    private func makeUniforms(deltaTime: Float, time: Float) -> ParticleUniforms {
        let (emitterType, param1, param2) = emitterParams()

        return ParticleUniforms(
            deltaTime: deltaTime,
            time: time,
            particleCount: UInt32(count),
            forceCount: UInt32(forces.count),
            emissionRate: emissionRate,
            particleLife: particleLife,
            particleSize: particleSize,
            startColor: startColor,
            endColor: endColor,
            emitterType: emitterType,
            emitterParam1: param1,
            emitterParam2: param2
        )
    }

    /// Convert the current emitter shape to GPU-compatible parameters.
    private func emitterParams() -> (UInt32, SIMD4<Float>, SIMD4<Float>) {
        switch emitter {
        case .point(let x, let y, let z):
            return (0, SIMD4(x, y, z, 0), .zero)
        case .line(let x1, let y1, let z1, let x2, let y2, let z2):
            return (1, SIMD4(x1, y1, z1, 0), SIMD4(x2, y2, z2, 0))
        case .circle(let x, let y, let z, let r):
            return (2, SIMD4(x, y, z, 0), SIMD4(r, 0, 0, 0))
        case .sphere(let x, let y, let z, let r):
            return (3, SIMD4(x, y, z, 0), SIMD4(r, 0, 0, 0))
        }
    }

    /// Rebuild the GPU force buffer from the current forces array.
    private func rebuildForceBuffer() {
        var descriptors: [ForceDescriptor] = []
        for force in forces {
            switch force {
            case .gravity(let x, let y, let z):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(0, x, y, z),
                    strengthAndExtra: SIMD4(1, 0, 0, 0)
                ))
            case .attraction(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(1, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .repulsion(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(2, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .noise(let scale, let strength):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(3, 0, 0, 0),
                    strengthAndExtra: SIMD4(strength, scale, 0, 0)
                ))
            case .vortex(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(4, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .damping(let factor):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(5, 0, 0, 0),
                    strengthAndExtra: SIMD4(factor, 0, 0, 0)
                ))
            }
        }

        if descriptors.isEmpty {
            forceBuffer = nil
        } else {
            forceBuffer = device.makeBuffer(
                bytes: descriptors,
                length: MemoryLayout<ForceDescriptor>.stride * descriptors.count,
                options: .storageModeShared
            )
        }
    }
}

