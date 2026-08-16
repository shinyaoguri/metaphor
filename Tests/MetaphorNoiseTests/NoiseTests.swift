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

    // 失敗系: colorStops は 2 個以上が必須(doc に明記した nil 条件の凍結)

    @Test("color mapped texture returns nil for empty stops")
    @MainActor func colorMappedTextureEmptyStops() {
        let device = MTLCreateSystemDefaultDevice()!
        let values: [Float] = Array(repeating: 0.5, count: 16)
        let texture = NoiseTextureBuilder.buildColorMappedTexture(
            device: device, values: values, width: 4, height: 4,
            colorStops: []
        )
        #expect(texture == nil)
    }

    @Test("color mapped texture returns nil for a single stop")
    @MainActor func colorMappedTextureSingleStop() {
        let device = MTLCreateSystemDefaultDevice()!
        let values: [Float] = Array(repeating: 0.5, count: 16)
        let texture = NoiseTextureBuilder.buildColorMappedTexture(
            device: device, values: values, width: 4, height: 4,
            colorStops: [(0.0, SIMD4(0, 0, 0, 255))]
        )
        #expect(texture == nil)
    }

    @Test("color mapped texture returns nil for values/size mismatch")
    @MainActor func colorMappedTextureSizeMismatch() {
        let device = MTLCreateSystemDefaultDevice()!
        let values: [Float] = Array(repeating: 0.5, count: 15)  // 4x4 に 1 個足りない
        let texture = NoiseTextureBuilder.buildColorMappedTexture(
            device: device, values: values, width: 4, height: 4,
            colorStops: [
                (0.0, SIMD4(0, 0, 0, 255)),
                (1.0, SIMD4(255, 255, 255, 255)),
            ]
        )
        #expect(texture == nil)
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

// MARK: - 点サンプリングとグリッドの座標系（#785）

/// `sample(x:y:)` と `sampleGrid` / `texture` / `image` は別の座標系で場を読む。
/// これは直せない非対称ではなく **doc で約束した仕様** なので、崩れたら気付けるように固定する。
///
/// - `sample(x:y:)` は `origin` / `sampleScale` を一切通さない生のノイズ空間
/// - グリッド系は `origin` を起点に `GKNoiseMap` へ委ねる（刻みは GameplayKit 側の都合で決まる）
@Suite("GKNoiseWrapper coordinate spaces", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct NoiseCoordinateSpaceTests {

    /// octaves 1 / frequency 1.0 なら 1 単位程度で値がよく動くので、
    /// 座標がずれていれば必ず値の差として現れる。
    private func makeConfig() -> NoiseConfig {
        var config = NoiseConfig(octaves: 1, frequency: 1.0, seed: 21)
        config.normalized = false
        return config
    }

    /// 格子点ちょうど（整数座標）は Perlin が 0 を返して差が出ないので、必ず格子から外す。
    private let probePoints: [(Float, Float)] = [
        (0.37, 0.61), (1.7, 2.3), (5.5, 8.1), (0.01, 9.9), (-3.25, 4.75),
    ]

    @Test("origin does not move sample(x:y:)")
    func originDoesNotMovePointSampling() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: makeConfig(), device: device)

        let before = probePoints.map { wrapper.sample(x: $0.0, y: $0.1) }

        var config = wrapper.config
        config.origin = SIMD2(5.0, -7.0)
        wrapper.config = config

        // 1 ビットも動かないことを固定する（差ではなく完全一致で見る）
        let after = probePoints.map { wrapper.sample(x: $0.0, y: $0.1) }
        #expect(before == after)
    }

    @Test("sampleScale does not scale sample(x:y:)")
    func sampleScaleDoesNotScalePointSampling() {
        let device = MTLCreateSystemDefaultDevice()!
        let wrapper = GKNoiseWrapper(type: .perlin, config: makeConfig(), device: device)

        let before = probePoints.map { wrapper.sample(x: $0.0, y: $0.1) }

        var config = wrapper.config
        config.sampleScale = SIMD2(3.0, 3.0)
        wrapper.config = config

        let after = probePoints.map { wrapper.sample(x: $0.0, y: $0.1) }
        #expect(before == after)
    }

    @Test("origin is the grid's first sample")
    func gridStartsAtOrigin() {
        let device = MTLCreateSystemDefaultDevice()!
        var config = makeConfig()
        config.origin = SIMD2(0.35, -0.75)
        config.sampleScale = SIMD2(1.0, 1.0)
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)

        let grid = wrapper.sampleGrid(width: 64, height: 64)
        let atOrigin = wrapper.sample(x: config.origin.x, y: config.origin.y)

        // grid の起点だけは点サンプリングと一致する（doc の「最初の 1 点だけ重なる」の根拠）
        #expect(abs(grid[0] - atOrigin) < 1e-6)
    }

    // 失敗系: 起点を合わせても 2 点目以降は一致しない（一致させられない、が doc の約束）

    @Test("grid values past the first sample do not match sample(x:y:)")
    func gridDivergesFromPointSampling() {
        let device = MTLCreateSystemDefaultDevice()!
        var config = makeConfig()
        config.origin = SIMD2(0.35, -0.75)
        config.sampleScale = SIMD2(1.0, 1.0)
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)

        let grid = wrapper.sampleGrid(width: 64, height: 64)

        // origin + index × sampleScale で追いかけても追随しない
        var maxDiff: Float = 0
        for i in 1..<16 {
            let expected = wrapper.sample(
                x: config.origin.x + Double(i) * config.sampleScale.x,
                y: config.origin.y
            )
            maxDiff = max(maxDiff, abs(grid[i] - expected))
        }
        #expect(maxDiff > 0.05)
    }

    // 境界値: 同じ sampleScale でも格子の大きさを変えると同じ index が別の座標を指す

    @Test("grid step depends on the grid size, not on sampleScale alone")
    func gridStepDependsOnGridSize() {
        let device = MTLCreateSystemDefaultDevice()!
        var config = makeConfig()
        config.origin = SIMD2(0.35, -0.75)
        config.sampleScale = SIMD2(1.0, 1.0)
        let wrapper = GKNoiseWrapper(type: .perlin, config: config, device: device)

        let wide = wrapper.sampleGrid(width: 64, height: 64)
        let narrow = wrapper.sampleGrid(width: 16, height: 16)

        // 起点だけは格子の大きさによらず一致する
        #expect(abs(wide[0] - narrow[0]) < 1e-6)

        // 刻みが sampleScale だけで決まるなら行 0 は前半 16 点まで一致するはずだが、しない
        var maxDiff: Float = 0
        for i in 1..<16 {
            maxDiff = max(maxDiff, abs(wide[i] - narrow[i]))
        }
        #expect(maxDiff > 0.01)
    }
}
