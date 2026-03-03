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

    @Test("ParticleUniforms is correctly sized")
    func uniformsSize() {
        // 4 floats(16) + 2 SIMD4(32) + 4 uint32(16) + 2 SIMD4(32) = 96 bytes
        let stride = MemoryLayout<ParticleUniforms>.stride
        #expect(stride > 0)
        // 16-byte aligned
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
        let lib = try device.makeLibrary(source: ParticleShaders.source, options: nil)

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

// MARK: - ParticleForce

@Suite("ParticleForce")
struct ParticleForceTests {

    @Test("Gravity force")
    func gravityForce() {
        let force = ParticleForce.gravity(0, -9.8, 0)
        if case .gravity(let x, let y, let z) = force {
            #expect(x == 0)
            #expect(y == -9.8)
            #expect(z == 0)
        } else {
            Issue.record("Expected gravity force")
        }
    }

    @Test("Noise force")
    func noiseForce() {
        let force = ParticleForce.noise(scale: 0.01, strength: 2.0)
        if case .noise(let s, let str) = force {
            #expect(s == 0.01)
            #expect(str == 2.0)
        } else {
            Issue.record("Expected noise force")
        }
    }

    @Test("Damping force")
    func dampingForce() {
        let force = ParticleForce.damping(0.95)
        if case .damping(let f) = force {
            #expect(f == 0.95)
        } else {
            Issue.record("Expected damping force")
        }
    }
}

// MARK: - EmitterShape

@Suite("EmitterShape")
struct EmitterShapeTests {

    @Test("Point emitter")
    func pointEmitter() {
        let shape = EmitterShape.point(1, 2, 3)
        if case .point(let x, let y, let z) = shape {
            #expect(x == 1)
            #expect(y == 2)
            #expect(z == 3)
        } else {
            Issue.record("Expected point emitter")
        }
    }

    @Test("Sphere emitter")
    func sphereEmitter() {
        let shape = EmitterShape.sphere(x: 0, y: 0, z: 0, radius: 5.0)
        if case .sphere(let x, let y, let z, let r) = shape {
            #expect(x == 0)
            #expect(y == 0)
            #expect(z == 0)
            #expect(r == 5.0)
        } else {
            Issue.record("Expected sphere emitter")
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
