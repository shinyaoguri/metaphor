import Testing
import Metal
import simd
@testable import MetaphorCore

@Suite("ShadowMap", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShadowMapTests {
    let device: MTLDevice
    let shaderLibrary: ShaderLibrary

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        self.device = device
        self.shaderLibrary = try ShaderLibrary(device: device)
    }

    // MARK: - Initialization

    @Test("ShadowMap creates depth texture with correct resolution")
    func shadowMapCreation() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 1024)
        #expect(shadow.resolution == 1024)
        #expect(shadow.shadowTexture.width == 1024)
        #expect(shadow.shadowTexture.height == 1024)
        #expect(shadow.shadowTexture.pixelFormat == .depth32Float)
    }

    @Test("ShadowMap default resolution is 2048")
    func shadowMapDefaultResolution() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary)
        #expect(shadow.resolution == 2048)
        #expect(shadow.shadowTexture.width == 2048)
    }

    @Test("ShadowMap depth texture has correct usage")
    func shadowMapTextureUsage() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        let usage = shadow.shadowTexture.usage
        #expect(usage.contains(.renderTarget))
        #expect(usage.contains(.shaderRead))
    }

    // MARK: - Properties

    @Test("ShadowMap default bias value")
    func defaultBias() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        #expect(abs(shadow.shadowBias - 0.005) < 1e-6)
    }

    @Test("ShadowMap bias can be changed")
    func changeBias() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        shadow.shadowBias = 0.01
        #expect(abs(shadow.shadowBias - 0.01) < 1e-6)
    }

    @Test("ShadowMap default PCF radius")
    func defaultPcfRadius() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        #expect(shadow.pcfRadius == 2)
    }

    // MARK: - Light Space Matrix

    @Test("lightSpaceMatrix starts as identity")
    func initialLightSpaceMatrix() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        let identity = float4x4.identity
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(shadow.lightSpaceMatrix[col][row] - identity[col][row]) < 1e-5)
            }
        }
    }

    @Test("updateLightSpaceMatrix produces non-identity matrix")
    func updateLightSpaceMatrix() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        shadow.updateLightSpaceMatrix(
            lightDirection: SIMD3(0.5, -1, 0.5),
            sceneCenter: .zero,
            sceneRadius: 100
        )
        // Should no longer be identity
        let m = shadow.lightSpaceMatrix
        let isIdentity = (0..<4).allSatisfy { col in
            (0..<4).allSatisfy { row in
                abs(m[col][row] - (col == row ? 1.0 : 0.0)) < 1e-4
            }
        }
        #expect(!isIdentity)
    }

    @Test("updateLightSpaceMatrix handles vertical light direction")
    func verticalLightDirection() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        // Straight down — should use alternate up vector
        shadow.updateLightSpaceMatrix(
            lightDirection: SIMD3(0, -1, 0),
            sceneCenter: .zero,
            sceneRadius: 200
        )
        let m = shadow.lightSpaceMatrix
        // Matrix should be finite and valid
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(m[col][row].isFinite)
            }
        }
    }

    // MARK: - Shadow Depth Rendering

    @Test("ShadowMap render with empty draw calls succeeds")
    func renderEmptyDrawCalls() throws {
        let shadow = try ShadowMap(device: device, shaderLibrary: shaderLibrary, resolution: 512)
        shadow.updateLightSpaceMatrix(lightDirection: SIMD3(0, -1, 0.5))

        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            return
        }

        shadow.render(drawCalls: [], commandBuffer: cmdBuf)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        // No crash = success
    }

    // MARK: - Struct Sizes

    @Test("ShadowUniforms has correct size")
    func shadowUniformsSize() {
        let size = MemoryLayout<ShadowUniforms>.stride
        // 2 x float4x4 = 2 * 64 = 128 bytes
        #expect(size == 128)
    }

    @Test("ShadowFragmentUniforms has correct size")
    func shadowFragmentUniformsSize() {
        let size = MemoryLayout<ShadowFragmentUniforms>.stride
        // float4x4(64) + Float(4) + Float(4) + SIMD2<Float>(8) = 80 bytes
        #expect(size == 80)
    }
}
