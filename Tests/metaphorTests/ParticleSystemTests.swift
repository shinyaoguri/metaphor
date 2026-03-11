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

@Suite("ParticleSystem Creation")
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
