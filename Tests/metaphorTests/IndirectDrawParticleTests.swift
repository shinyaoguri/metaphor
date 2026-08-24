import Testing
import Metal
@testable import MetaphorCore

// MARK: - C-15: Indirect Draw Particle

@Suite("C-15 Indirect Draw Particle", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct IndirectDrawParticleTests {

    @Test("ParticleSystem useIndirectDraw defaults to false")
    func defaultsOff() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(
            device: device, shaderLibrary: library, sampleCount: 4, count: 1000)
        #expect(ps.useIndirectDraw == false)
    }

    @Test("ParticleSystem can enable indirect draw")
    func enableIndirectDraw() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(
            device: device, shaderLibrary: library, sampleCount: 4, count: 1000)
        ps.useIndirectDraw = true
        #expect(ps.useIndirectDraw == true)
    }

    @Test("ParticleSystem with indirect draw doesn't crash on update")
    func indirectDrawUpdate() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(
            device: device, shaderLibrary: library, sampleCount: 4, count: 100)
        ps.useIndirectDraw = true

        let queue = device.makeCommandQueue()!
        let cb = queue.makeCommandBuffer()!
        let encoder = cb.makeComputeCommandEncoder()!
        ps.update(encoder: encoder, deltaTime: 1.0 / 60.0, time: 0.0)
        encoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        #expect(cb.status == .completed)
        #expect(ps.count == 100)
    }
}
