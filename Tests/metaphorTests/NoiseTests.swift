import Testing
import Metal
import GameplayKit
import simd
@testable import metaphor
@testable import MetaphorCore
@testable import MetaphorNoise

// MARK: - NoiseType Tests

@Suite("NoiseType")
struct NoiseTypeTests {

    @Test("all cases are constructible")
    func allCases() {
        let types: [NoiseType] = [
            .perlin, .voronoi, .billow, .ridged,
            .cylinders, .spheres, .checkerboard,
            .constant(value: 0.5),
        ]
        #expect(types.count == 8)
    }

    @Test("constant value")
    func constantValue() {
        let noise = NoiseType.constant(value: 0.42)
        if case .constant(let v) = noise {
            #expect(abs(v - 0.42) < 0.001)
        } else {
            Issue.record("Expected constant case")
        }
    }

    @Test("sendable conformance")
    func sendable() {
        let noise: any Sendable = NoiseType.perlin
        _ = noise
    }
}

// MARK: - NoiseConfig Tests

@Suite("NoiseConfig")
struct NoiseConfigTests {

    @Test("default values")
    func defaults() {
        let config = NoiseConfig()
        #expect(config.octaves == 6)
        #expect(config.frequency == 1.0)
        #expect(config.lacunarity == 2.0)
        #expect(config.seed == 0)
        #expect(config.persistence == 0.5)
        #expect(config.normalized == true)
        #expect(config.voronoiDistanceEnabled == true)
        #expect(config.sampleScale == SIMD2(1.0, 1.0))
        #expect(config.origin == .zero)
    }

    @Test("custom values")
    func customValues() {
        var config = NoiseConfig()
        config.octaves = 4
        config.frequency = 2.5
        config.seed = 42
        config.normalized = false
        #expect(config.octaves == 4)
        #expect(config.frequency == 2.5)
        #expect(config.seed == 42)
        #expect(config.normalized == false)
    }

    @Test("sendable conformance")
    func sendable() {
        let config: any Sendable = NoiseConfig()
        _ = config
    }
}

// MARK: - GKNoiseWrapper Tests

@Suite("GKNoiseWrapper")
struct GKNoiseWrapperTests {

    @Test("perlin noise creation")
    @MainActor func perlinCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("voronoi noise creation")
    @MainActor func voronoiCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .voronoi, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("billow noise creation")
    @MainActor func billowCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .billow, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("ridged noise creation")
    @MainActor func ridgedCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .ridged, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("cylinders noise creation")
    @MainActor func cylindersCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .cylinders, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("spheres noise creation")
    @MainActor func spheresCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .spheres, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("checkerboard noise creation")
    @MainActor func checkerboardCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .checkerboard, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("constant noise creation")
    @MainActor func constantCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .constant(value: 0.5), config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("sample returns float value")
    @MainActor func sampleValue() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let value = wrapper.sample(x: 0.5, y: 0.3)
        // Perlin noise output is bounded
        #expect(value.isFinite)
    }

    @Test("sampleGrid returns correct count")
    @MainActor func sampleGrid() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let grid = wrapper.sampleGrid(width: 16, height: 16)
        #expect(grid.count == 256)
    }

    @Test("sampleGrid values are finite")
    @MainActor func sampleGridFinite() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .voronoi, config: NoiseConfig(), device: device)
        let grid = wrapper.sampleGrid(width: 8, height: 8)
        for value in grid {
            #expect(value.isFinite)
        }
    }

    @Test("normalized config clamps to 0-1")
    @MainActor func normalizedOutput() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var config = NoiseConfig()
        config.normalized = true
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)
        let grid = wrapper.sampleGrid(width: 32, height: 32)
        for value in grid {
            #expect(value >= 0.0)
            #expect(value <= 1.0)
        }
    }

    @Test("texture generation")
    @MainActor func textureGeneration() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let texture = wrapper.texture(width: 32, height: 32)
        #expect(texture != nil)
        #expect(texture?.width == 32)
        #expect(texture?.height == 32)
        #expect(texture?.pixelFormat == .bgra8Unorm)
    }

    @Test("image generation")
    @MainActor func imageGeneration() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .billow, config: NoiseConfig(), device: device)
        let image = wrapper.image(width: 16, height: 16)
        #expect(image != nil)
    }

    @Test("invert operation")
    @MainActor func invertOperation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let beforeGrid = wrapper.sampleGrid(width: 8, height: 8)
        wrapper.invert()
        let afterGrid = wrapper.sampleGrid(width: 8, height: 8)
        // At least some values should differ
        var anyDifferent = false
        for i in 0..<beforeGrid.count {
            if abs(beforeGrid[i] - afterGrid[i]) > 0.001 {
                anyDifferent = true
                break
            }
        }
        #expect(anyDifferent)
    }

    @Test("applyAbsoluteValue operation")
    @MainActor func absOperation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var config = NoiseConfig()
        config.normalized = false
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)
        wrapper.applyAbsoluteValue()
        let grid = wrapper.sampleGrid(width: 16, height: 16)
        for value in grid {
            #expect(value >= 0.0)
        }
    }

    @Test("clamp operation")
    @MainActor func clampOperation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var config = NoiseConfig()
        config.normalized = false
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)
        wrapper.clamp(min: 0.0, max: 0.5)
        let grid = wrapper.sampleGrid(width: 16, height: 16)
        for value in grid {
            #expect(value >= -0.01)  // Small tolerance
            #expect(value <= 0.51)
        }
    }

    @Test("different seeds produce different noise")
    @MainActor func differentSeeds() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var config1 = NoiseConfig()
        config1.seed = 1
        var config2 = NoiseConfig()
        config2.seed = 999

        let wrapper1 = GKNoiseWrapper(type: .perlin, config: config1, device: device)
        let wrapper2 = GKNoiseWrapper(type: .perlin, config: config2, device: device)

        let grid1 = wrapper1.sampleGrid(width: 8, height: 8)
        let grid2 = wrapper2.sampleGrid(width: 8, height: 8)

        var anyDifferent = false
        for i in 0..<grid1.count {
            if abs(grid1[i] - grid2[i]) > 0.001 {
                anyDifferent = true
                break
            }
        }
        #expect(anyDifferent)
    }
}

// MARK: - NoiseTextureBuilder Tests

@Suite("NoiseTextureBuilder")
struct NoiseTextureBuilderTests {

    @Test("build grayscale texture")
    @MainActor func buildGrayscaleTexture() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let values: [Float] = Array(repeating: 0.5, count: 16)
        let texture = NoiseTextureBuilder.buildTexture(
            device: device, values: values, width: 4, height: 4
        )
        #expect(texture != nil)
        #expect(texture?.width == 4)
        #expect(texture?.height == 4)
    }

    @Test("build color mapped texture")
    @MainActor func buildColorMappedTexture() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let values: [Float] = (0..<64).map { Float($0) / 63.0 }
        let stops: [(Float, SIMD4<UInt8>)] = [
            (0.0, SIMD4(0, 0, 0, 255)),
            (1.0, SIMD4(255, 255, 255, 255)),
        ]
        let texture = NoiseTextureBuilder.buildColorMappedTexture(
            device: device, values: values, width: 8, height: 8,
            colorStops: stops
        )
        #expect(texture != nil)
        #expect(texture?.width == 8)
        #expect(texture?.height == 8)
    }
}
