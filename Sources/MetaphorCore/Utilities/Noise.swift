import Foundation

/// Generate Perlin noise in 1D, 2D, and 3D.
///
/// Produces noise values in the range 0.0 to 1.0.
/// Use octaves and falloff to control fractal noise detail.
public struct NoiseGenerator: Sendable {
    /// Number of octaves (layers to combine).
    public var octaves: Int = 4

    /// Amplitude decay rate per octave.
    public var falloff: Float = 0.5

    /// Permutation table stored as Int32 for cache efficiency (2KB vs 4KB).
    @usableFromInline
    let perm: ContiguousArray<Int32>

    // MARK: - Initialization

    /// Create a noise generator with the given seed value.
    /// - Parameter seed: The seed for the permutation table. Use 0 for the default table.
    public init(seed: UInt64 = 0) {
        var base = Self.defaultPermutation
        if seed != 0 {
            var rng = seed
            for i in stride(from: 255, through: 1, by: -1) {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let j = Int(rng >> 33) % (i + 1)
                base.swapAt(i, j)
            }
        }
        self.perm = ContiguousArray(base + base)
    }

    // MARK: - Public Interface

    /// Sample 1D noise at the given coordinate.
    /// - Parameter x: The input coordinate.
    /// - Returns: A noise value in the range 0.0 to 1.0.
    @inlinable
    public func noise(_ x: Float) -> Float {
        perm.withUnsafeBufferPointer { p in
            var total: Float = 0
            var amplitude: Float = 1
            var frequency: Float = 1
            var maxAmplitude: Float = 0
            for _ in 0..<octaves {
                total += rawNoise1D(x * frequency, p) * amplitude
                maxAmplitude += amplitude
                amplitude *= falloff
                frequency *= 2
            }
            return (total / maxAmplitude + 1) * 0.5
        }
    }

    /// Sample 2D noise at the given coordinates.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    /// - Returns: A noise value in the range 0.0 to 1.0.
    @inlinable
    public func noise(_ x: Float, _ y: Float) -> Float {
        perm.withUnsafeBufferPointer { p in
            var total: Float = 0
            var amplitude: Float = 1
            var frequency: Float = 1
            var maxAmplitude: Float = 0
            for _ in 0..<octaves {
                total += rawNoise2D(x * frequency, y * frequency, p) * amplitude
                maxAmplitude += amplitude
                amplitude *= falloff
                frequency *= 2
            }
            return (total / maxAmplitude + 1) * 0.5
        }
    }

    /// Sample 3D noise at the given coordinates.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - z: The z coordinate.
    /// - Returns: A noise value in the range 0.0 to 1.0.
    @inlinable
    public func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
        perm.withUnsafeBufferPointer { p in
            var total: Float = 0
            var amplitude: Float = 1
            var frequency: Float = 1
            var maxAmplitude: Float = 0
            for _ in 0..<octaves {
                total += rawNoise3D(x * frequency, y * frequency, z * frequency, p) * amplitude
                maxAmplitude += amplitude
                amplitude *= falloff
                frequency *= 2
            }
            return (total / maxAmplitude + 1) * 0.5
        }
    }

    // MARK: - Internal

    /// Compute a single octave of 1D Perlin noise (range: -1 to 1).
    /// Specialized path: skips y/z dimensions entirely.
    @inlinable
    func rawNoise1D(
        _ x: Float,
        _ p: UnsafeBufferPointer<Int32>
    ) -> Float {
        let fx = floor(x)
        let xi = Int(fx) & 255
        let xf = x - fx
        let u = fade(xf)

        let aa = Int(p[Int(p[xi])])
        let ba = Int(p[Int(p[xi + 1])])

        return mix(grad1D(aa, xf), grad1D(ba, xf - 1), u)
    }

    /// Compute a single octave of 2D Perlin noise (range: -1 to 1).
    /// Specialized path: skips z dimension (saves ~40% vs 3D).
    @inlinable
    func rawNoise2D(
        _ x: Float, _ y: Float,
        _ p: UnsafeBufferPointer<Int32>
    ) -> Float {
        let fx = floor(x)
        let fy = floor(y)

        let xi = Int(fx) & 255
        let yi = Int(fy) & 255

        let xf = x - fx
        let yf = y - fy

        let u = fade(xf)
        let v = fade(yf)

        let pxi = Int(p[xi])
        let pxi1 = Int(p[xi + 1])

        let aa = Int(p[Int(p[pxi + yi])])
        let ab = Int(p[Int(p[pxi + yi + 1])])
        let ba = Int(p[Int(p[pxi1 + yi])])
        let bb = Int(p[Int(p[pxi1 + yi + 1])])

        let x1 = mix(grad2D(aa, xf, yf), grad2D(ba, xf - 1, yf), u)
        let x2 = mix(grad2D(ab, xf, yf - 1), grad2D(bb, xf - 1, yf - 1), u)

        return mix(x1, x2, v)
    }

    /// Compute a single octave of 3D Perlin noise (range: -1 to 1).
    @inlinable
    func rawNoise3D(
        _ x: Float, _ y: Float, _ z: Float,
        _ p: UnsafeBufferPointer<Int32>
    ) -> Float {
        let fx = floor(x)
        let fy = floor(y)
        let fz = floor(z)

        let xi = Int(fx) & 255
        let yi = Int(fy) & 255
        let zi = Int(fz) & 255

        let xf = x - fx
        let yf = y - fy
        let zf = z - fz

        let u = fade(xf)
        let v = fade(yf)
        let w = fade(zf)

        let pxi = Int(p[xi])
        let pxi1 = Int(p[xi + 1])
        let pA = Int(p[pxi + yi])
        let pB = Int(p[pxi + yi + 1])
        let pC = Int(p[pxi1 + yi])
        let pD = Int(p[pxi1 + yi + 1])

        let aaa = Int(p[pA + zi])
        let aba = Int(p[pB + zi])
        let aab = Int(p[pA + zi + 1])
        let abb = Int(p[pB + zi + 1])
        let baa = Int(p[pC + zi])
        let bba = Int(p[pD + zi])
        let bab = Int(p[pC + zi + 1])
        let bbb = Int(p[pD + zi + 1])

        let x1 = mix(grad3D(aaa, xf, yf, zf), grad3D(baa, xf - 1, yf, zf), u)
        let x2 = mix(grad3D(aba, xf, yf - 1, zf), grad3D(bba, xf - 1, yf - 1, zf), u)
        let y1 = mix(x1, x2, v)

        let x3 = mix(grad3D(aab, xf, yf, zf - 1), grad3D(bab, xf - 1, yf, zf - 1), u)
        let x4 = mix(grad3D(abb, xf, yf - 1, zf - 1), grad3D(bbb, xf - 1, yf - 1, zf - 1), u)
        let y2 = mix(x3, x4, v)

        return mix(y1, y2, w)
    }

    @inlinable
    func fade(_ t: Float) -> Float {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    @inlinable
    func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + t * (b - a)
    }

    @inlinable
    func grad1D(_ hash: Int, _ x: Float) -> Float {
        (hash & 1) == 0 ? x : -x
    }

    @inlinable
    func grad2D(_ hash: Int, _ x: Float, _ y: Float) -> Float {
        let h = hash & 15
        let u: Float = h < 8 ? x : y
        let v: Float = h < 4 ? y : (h == 12 || h == 14 ? x : 0)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }

    @inlinable
    func grad3D(_ hash: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let h = hash & 15
        let u: Float = h < 8 ? x : y
        let v: Float = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }

    // MARK: - Default Permutation Table (Ken Perlin)

    private static let defaultPermutation: [Int32] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
        247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
        57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
        74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
        60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
        65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
        200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
        52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
        207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
        119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
        129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
        218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
        81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
        184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
        222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
    ]
}

// MARK: - Global Noise Functions

/// Global noise generator scoped to MainActor.
@MainActor
private var _noiseGenerator = NoiseGenerator()

/// Sample 1D Perlin noise at the given coordinate.
/// - Parameter x: The input coordinate.
/// - Returns: A noise value in the range 0.0 to 1.0.
@MainActor
public func noise(_ x: Float) -> Float {
    _noiseGenerator.noise(x)
}

/// Sample 2D Perlin noise at the given coordinates.
/// - Parameters:
///   - x: The x coordinate.
///   - y: The y coordinate.
/// - Returns: A noise value in the range 0.0 to 1.0.
@MainActor
public func noise(_ x: Float, _ y: Float) -> Float {
    _noiseGenerator.noise(x, y)
}

/// Sample 3D Perlin noise at the given coordinates.
/// - Parameters:
///   - x: The x coordinate.
///   - y: The y coordinate.
///   - z: The z coordinate.
/// - Returns: A noise value in the range 0.0 to 1.0.
@MainActor
public func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
    _noiseGenerator.noise(x, y, z)
}

/// Configure the noise detail level by setting octaves and falloff.
/// - Parameters:
///   - octaves: The number of noise layers to combine.
///   - falloff: The amplitude decay rate per octave.
@MainActor
public func noiseDetail(octaves: Int = 4, falloff: Float = 0.5) {
    _noiseGenerator.octaves = octaves
    _noiseGenerator.falloff = falloff
}

/// Reinitialize the noise generator with a new seed value.
/// - Parameter seed: The seed for the permutation table.
@MainActor
public func noiseSeed(_ seed: UInt64) {
    _noiseGenerator = NoiseGenerator(seed: seed)
}
