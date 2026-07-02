import Testing
import Metal
import GameplayKit
import simd
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

@Suite("GKNoiseWrapper", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GKNoiseWrapperTests {

    @Test("perlin noise creation")
    @MainActor func perlinCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("voronoi noise creation")
    @MainActor func voronoiCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .voronoi, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("billow noise creation")
    @MainActor func billowCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .billow, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("ridged noise creation")
    @MainActor func ridgedCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .ridged, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("cylinders noise creation")
    @MainActor func cylindersCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .cylinders, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("spheres noise creation")
    @MainActor func spheresCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .spheres, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("checkerboard noise creation")
    @MainActor func checkerboardCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .checkerboard, config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("constant noise creation")
    @MainActor func constantCreation() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .constant(value: 0.5), config: NoiseConfig(), device: device)
        _ = wrapper
    }

    @Test("sample returns float value")
    @MainActor func sampleValue() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let value = wrapper.sample(x: 0.5, y: 0.3)
        // Perlin noise output is bounded
        #expect(value.isFinite)
    }

    @Test("sampleGrid returns correct count")
    @MainActor func sampleGrid() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let grid = wrapper.sampleGrid(width: 16, height: 16)
        #expect(grid.count == 256)
    }

    @Test("sampleGrid values are finite")
    @MainActor func sampleGridFinite() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .voronoi, config: NoiseConfig(), device: device)
        let grid = wrapper.sampleGrid(width: 8, height: 8)
        for value in grid {
            #expect(value.isFinite)
        }
    }

    @Test("normalized config clamps to 0-1")
    @MainActor func normalizedOutput() {
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)
        let texture = wrapper.texture(width: 32, height: 32)
        #expect(texture != nil)
        #expect(texture?.width == 32)
        #expect(texture?.height == 32)
        #expect(texture?.pixelFormat == .bgra8Unorm)
    }

    @Test("image generation")
    @MainActor func imageGeneration() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .billow, config: NoiseConfig(), device: device)
        let image = wrapper.image(width: 16, height: 16)
        #expect(image != nil)
    }

    @Test("invert operation")
    @MainActor func invertOperation() {
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
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
        let device = MTLCreateSystemDefaultDevice()!
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

// MARK: - config 変更のソース再構築（#143）

@Suite("GKNoiseWrapper config rebuild")
@MainActor
struct NoiseConfigRebuildTests {

    @Test("changing seed changes sample output")
    func seedChangeReflects() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)

        // 複数点で比較する（単一点では偶然一致し得るため）
        let points: [(Float, Float)] = [(0.13, 0.29), (1.7, 2.3), (5.5, 8.1), (0.01, 9.9)]
        let before = points.map { wrapper.sample(x: $0.0, y: $0.1) }

        var config = wrapper.config
        config.seed = 424_242
        wrapper.config = config

        // 修正前は init 時の GKNoise が再構築されず、seed 変更が反映されなかった
        let after = points.map { wrapper.sample(x: $0.0, y: $0.1) }
        #expect(before != after)
    }

    @Test("changing frequency changes sample output")
    func frequencyChangeReflects() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)

        let points: [(Float, Float)] = [(0.13, 0.29), (1.7, 2.3), (5.5, 8.1), (0.01, 9.9)]
        let before = points.map { wrapper.sample(x: $0.0, y: $0.1) }

        var config = wrapper.config
        config.frequency = 8.0
        wrapper.config = config

        let after = points.map { wrapper.sample(x: $0.0, y: $0.1) }
        #expect(before != after)
    }

    @Test("sampleGrid cache is invalidated by config change")
    func gridCacheInvalidated() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: device)

        let before = wrapper.sampleGrid(width: 16, height: 16)

        var config = wrapper.config
        config.seed = 777
        wrapper.config = config

        let after = wrapper.sampleGrid(width: 16, height: 16)
        #expect(before != after)
    }
}
