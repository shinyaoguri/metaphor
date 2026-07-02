import Testing
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - Particle Struct

@Suite("Particle Struct")
struct ParticleStructTests {

    @Test("Particle stride is 64 bytes")
    func particleStride() {
        #expect(MemoryLayout<Particle>.stride == 64)
    }

    @Test("Particle size is 64 bytes")
    func particleSize() {
        #expect(MemoryLayout<Particle>.size == 64)
    }

    @Test("Particle alignment is 16")
    func particleAlignment() {
        #expect(MemoryLayout<Particle>.alignment == 16)
    }

    @Test("Default particle is zero-initialized")
    func defaultParticle() {
        let p = Particle()
        #expect(p.position == .zero)
        #expect(p.velocity == .zero)
        #expect(p.color == .zero)
        #expect(p.sizeAndFlags == .zero)
    }
}

// MARK: - ForceDescriptor Struct

@Suite("ForceDescriptor Struct")
struct ForceDescriptorTests {

    @Test("ForceDescriptor stride is 32 bytes")
    func forceDescriptorStride() {
        #expect(MemoryLayout<ForceDescriptor>.stride == 32)
    }
}

// MARK: - ParticleUniforms Struct

@Suite("ParticleUniforms Struct")
struct ParticleUniformsTests {

    @Test("ParticleUniforms stride is 112 bytes and 16-byte aligned")
    func uniformsSize() {
        let stride = MemoryLayout<ParticleUniforms>.stride
        // 8 floats(32) + 2 SIMD4(32) + 4 uint32(16) + 2 SIMD4(32) = 112 bytes
        #expect(stride == 112)
        #expect(stride % 16 == 0)
    }
}

// MARK: - ParticleRenderUniforms Struct

@Suite("ParticleRenderUniforms Struct")
struct ParticleRenderUniformsTests {

    @Test("ParticleRenderUniforms stride is 96 bytes")
    func renderUniformsStride() {
        // float4x4(64) + float4(16) + float4(16) = 96
        #expect(MemoryLayout<ParticleRenderUniforms>.stride == 96)
    }
}

// MARK: - Particle Shader Compilation

@Suite("Particle Shader Compilation")
struct ParticleShaderCompilationTests {

    @Test("Particle shader source compiles")
    @MainActor
    func shaderCompiles() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = try #require(ShaderLibrary.loadShaderSource("particle"))
        let lib = try device.makeLibrary(source: source, options: nil)

        let updateFn = lib.makeFunction(name: ParticleShaders.FunctionName.update)
        #expect(updateFn != nil)

        let vertexFn = lib.makeFunction(name: ParticleShaders.FunctionName.vertex)
        #expect(vertexFn != nil)

        let fragmentFn = lib.makeFunction(name: ParticleShaders.FunctionName.fragment)
        #expect(fragmentFn != nil)
    }

    @Test("ShaderLibrary registers particle key")
    @MainActor
    func shaderLibraryRegistration() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        #expect(lib.hasLibrary(for: ShaderLibrary.BuiltinKey.particle))
    }

    @Test("Can create compute pipeline from particle update shader")
    @MainActor
    func computePipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)

        let fn = lib.function(
            named: ParticleShaders.FunctionName.update,
            from: ShaderLibrary.BuiltinKey.particle
        )
        #expect(fn != nil)

        let pipeline = try device.makeComputePipelineState(function: fn!)
        #expect(pipeline.threadExecutionWidth > 0)
    }
}

// MARK: - ParticleForce (ForceBuffer 変換ロジック)

@Suite("ParticleForce", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ParticleForceTests {

    @Test("addForce gravity creates force buffer with correct type ID")
    @MainActor
    func gravityForceBuffer() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 10)

        system.addForce(.gravity(0, -9.8, 0))
        #expect(system.forces.count == 1)
        // addForce は内部で forceBuffer を作成する
        system.clearForces()
        #expect(system.forces.isEmpty)
    }

    @Test("multiple force types can coexist")
    @MainActor
    func multipleForceTypes() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 10)

        system.addForce(.gravity(0, -9.8, 0))
        system.addForce(.noise(scale: 0.01, strength: 2.0))
        system.addForce(.damping(0.95))
        system.addForce(.attraction(x: 0, y: 0, z: 0, strength: 5.0))
        system.addForce(.repulsion(x: 1, y: 0, z: 0, strength: 3.0))
        system.addForce(.vortex(x: 0, y: 1, z: 0, strength: 1.0))
        #expect(system.forces.count == 6)
    }
}

// MARK: - Emission Rate (GPU 実行)

@Suite("Particle Emission Rate", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ParticleEmissionRateTests {

    /// 指定フレーム数ぶん update カーネルを実行し、GPU 完了後の生存数を返します。
    @MainActor
    private func runFrames(
        _ system: ParticleSystem, device: MTLDevice, frames: Int, dt: Float
    ) throws -> Int {
        let queue = try #require(device.makeCommandQueue())
        var lastCB: MTLCommandBuffer?
        for i in 0..<frames {
            let cb = try #require(queue.makeCommandBuffer())
            let encoder = try #require(cb.makeComputeCommandEncoder())
            system.update(encoder: encoder, deltaTime: dt, time: Float(i) * dt)
            encoder.endEncoding()
            cb.commit()
            lastCB = cb
        }
        lastCB?.waitUntilCompleted()
        return system._currentParticlesForTesting.filter { $0.sizeAndFlags.w > 0.5 }.count
    }

    @Test("emission count matches emissionRate x dt exactly")
    @MainActor
    func exactEmissionPerFrame() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 1000)
        system.emissionRate = 600
        system.particleLife = 100  // テスト中は死なない

        // 1 フレーム（dt = 1/60）: 600 * 1/60 = ちょうど 10 個
        let alive = try runFrames(system, device: device, frames: 1, dt: 1.0 / 60.0)
        #expect(alive == 10)
    }

    @Test("emission rate does not decay as the pool fills (90% full)")
    @MainActor
    func noDecayAtHighFill() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 1000)
        system.emissionRate = 600
        system.particleLife = 100

        // 90 フレームでプールを 90% まで充填（10 個/フレーム）
        let at90 = try runFrames(system, device: device, frames: 90, dt: 1.0 / 60.0)
        #expect(at90 == 900)

        // 充填率 90% でも次のフレームでちょうど 10 個放出される
        // （旧実装は死候補にのみ確率適用するため約 1 個まで減衰していた）
        let afterOneMore = try runFrames(system, device: device, frames: 1, dt: 1.0 / 60.0)
        #expect(afterOneMore == 910)
    }

    @Test("fractional emission carries over between frames")
    @MainActor
    func fractionalAccumulation() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 100)
        system.emissionRate = 30  // 0.5 個/フレーム @ 60fps
        system.particleLife = 100

        // 2 フレームでちょうど 1 個（旧実装は低レートで放出が起きないことがある）
        let alive = try runFrames(system, device: device, frames: 2, dt: 1.0 / 60.0)
        #expect(alive == 1)
    }
}

// MARK: - EmitterShape (setEmitter ロジック)

@Suite("EmitterShape", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct EmitterShapeTests {

    @Test("setEmitter changes emitter shape")
    @MainActor
    func setEmitterChanges() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 10)

        // デフォルトは point(0,0,0)
        if case .point = system.emitter {} else {
            Issue.record("Expected default point emitter")
        }

        system.setEmitter(.sphere(x: 1, y: 2, z: 3, radius: 5.0))
        if case .sphere(let x, _, _, let r) = system.emitter {
            #expect(x == 1)
            #expect(r == 5.0)
        } else {
            Issue.record("Expected sphere emitter after setEmitter")
        }

        system.setEmitter(.line(x1: 0, y1: 0, z1: 0, x2: 10, y2: 0, z2: 0))
        if case .line = system.emitter {} else {
            Issue.record("Expected line emitter after setEmitter")
        }
    }
}

// MARK: - ParticleSystem Creation

@Suite("ParticleSystem Creation", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ParticleSystemCreationTests {

    @Test("Can create particle system")
    @MainActor
    func createSystem() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 1000)
        #expect(system.count == 1000)
    }

    @Test("Default properties")
    @MainActor
    func defaultProperties() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 100)

        #expect(system.emissionRate == 10000)
        #expect(system.particleLife == 2.0)
        #expect(system.particleSize == 0.05)
        #expect(system.forces.isEmpty)
    }

    @Test("Add and clear forces")
    @MainActor
    func forceManagement() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 100)

        system.addForce(.gravity(0, -9.8, 0))
        system.addForce(.noise(scale: 0.01, strength: 2.0))
        #expect(system.forces.count == 2)

        system.clearForces()
        #expect(system.forces.isEmpty)
    }

    @Test("Set emitter shape")
    @MainActor
    func setEmitter() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let lib = try ShaderLibrary(device: device)
        let system = try ParticleSystem(device: device, shaderLibrary: lib, sampleCount: 1, count: 100)

        system.setEmitter(.sphere(x: 0, y: 0, z: 0, radius: 1.0))
        if case .sphere(_, _, _, let r) = system.emitter {
            #expect(r == 1.0)
        } else {
            Issue.record("Expected sphere emitter")
        }
    }
}
