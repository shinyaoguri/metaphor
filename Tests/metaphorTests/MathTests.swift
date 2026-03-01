import Testing
import Metal
import simd
@testable import metaphor

// MARK: - Math Utility Tests

@Suite("Math Utilities")
struct MathUtilityTests {

    @Test("radians conversion")
    func radiansConversion() {
        let result = radians(180)
        #expect(abs(result - Float.pi) < 0.0001)
    }

    @Test("degrees conversion")
    func degreesConversion() {
        let result = degrees(Float.pi)
        #expect(abs(result - 180) < 0.0001)
    }

    @Test("lerp at boundaries")
    func lerpBoundaries() {
        #expect(lerp(Float(0), Float(10), Float(0)) == 0)
        #expect(lerp(Float(0), Float(10), Float(1)) == 10)
        #expect(lerp(Float(0), Float(10), Float(0.5)) == 5)
    }

    @Test("saturate clamps correctly")
    func saturateClamp() {
        #expect(saturate(-0.5) == 0)
        #expect(saturate(0.5) == 0.5)
        #expect(saturate(1.5) == 1)
    }

    @Test("smoothstep at boundaries")
    func smoothstepBoundaries() {
        #expect(smoothstep(0, 1, 0) == 0)
        #expect(smoothstep(0, 1, 1) == 1)
        let mid = smoothstep(0, 1, 0.5)
        #expect(abs(mid - 0.5) < 0.01)
    }

    @Test("identity matrix")
    func identityMatrix() {
        let id = float4x4.identity
        #expect(id.columns.0 == SIMD4<Float>(1, 0, 0, 0))
        #expect(id.columns.1 == SIMD4<Float>(0, 1, 0, 0))
        #expect(id.columns.2 == SIMD4<Float>(0, 0, 1, 0))
        #expect(id.columns.3 == SIMD4<Float>(0, 0, 0, 1))
    }

    @Test("translation matrix")
    func translationMatrix() {
        let t = float4x4(translation: SIMD3<Float>(1, 2, 3))
        #expect(t.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    }

    @Test("uniform scale matrix")
    func uniformScaleMatrix() {
        let s = float4x4(scale: Float(2))
        #expect(s.columns.0.x == 2)
        #expect(s.columns.1.y == 2)
        #expect(s.columns.2.z == 2)
        #expect(s.columns.3.w == 1)
    }
}

// MARK: - Time Utility Tests

@Suite("Time Utilities")
struct TimeUtilityTests {

    @Test("sine01 returns values in 0-1 range")
    func sine01Range() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = sine01(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("triangle returns values in 0-1 range")
    func triangleRange() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = triangle(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("sawtooth returns values in 0-1 range")
    func sawtoothRange() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = sawtooth(t)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("square returns 0 or 1")
    func squareValues() {
        for i in 0..<100 {
            let t = Double(i) * 0.1
            let v = square(t)
            #expect(v == 0 || v == 1)
        }
    }
}

// MARK: - Color Tests

@Suite("Color")
struct ColorTests {

    @Test("RGB init stores correct components")
    func rgbInit() {
        let c = Color(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        #expect(c.r == 0.2)
        #expect(c.g == 0.4)
        #expect(c.b == 0.6)
        #expect(c.a == 0.8)
    }

    @Test("RGB init defaults alpha to 1")
    func rgbDefaultAlpha() {
        let c = Color(r: 1, g: 0, b: 0)
        #expect(c.a == 1.0)
    }

    @Test("grayscale init sets equal RGB")
    func grayInit() {
        let c = Color(gray: 0.5)
        #expect(c.r == 0.5)
        #expect(c.g == 0.5)
        #expect(c.b == 0.5)
        #expect(c.a == 1.0)
    }

    @Test("HSB pure red")
    func hsbRed() {
        let c = Color(hue: 0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 1.0) < 0.001)
        #expect(abs(c.g - 0.0) < 0.001)
        #expect(abs(c.b - 0.0) < 0.001)
    }

    @Test("HSB pure green")
    func hsbGreen() {
        let c = Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 0.0) < 0.001)
        #expect(abs(c.g - 1.0) < 0.001)
        #expect(abs(c.b - 0.0) < 0.001)
    }

    @Test("HSB pure blue")
    func hsbBlue() {
        let c = Color(hue: 2.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.r - 0.0) < 0.001)
        #expect(abs(c.g - 0.0) < 0.001)
        #expect(abs(c.b - 1.0) < 0.001)
    }

    @Test("HSB zero saturation gives gray")
    func hsbGray() {
        let c = Color(hue: 0.5, saturation: 0, brightness: 0.7)
        #expect(abs(c.r - 0.7) < 0.001)
        #expect(abs(c.g - 0.7) < 0.001)
        #expect(abs(c.b - 0.7) < 0.001)
    }

    @Test("hex 0xRRGGBB")
    func hexRGB() {
        let c = Color(hex: 0xFF8000)
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.502) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
        #expect(c.a == 1.0)
    }

    @Test("hex 0xAARRGGBB")
    func hexARGB() {
        let c = Color(hex: 0x80FF0000)
        #expect(abs(c.a - 0.502) < 0.01)
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
    }

    @Test("hex string parsing")
    func hexString() {
        let c = Color(hex: "#FF0000")
        #expect(c != nil)
        #expect(c!.r == 1.0)
        #expect(c!.g == 0.0)
        #expect(c!.b == 0.0)
    }

    @Test("hex string invalid returns nil")
    func hexStringInvalid() {
        let c = Color(hex: "not-a-hex")
        #expect(c == nil)
    }

    @Test("SIMD conversion roundtrip")
    func simdConversion() {
        let original = Color(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        let reconstructed = Color(original.simd)
        #expect(original == reconstructed)
    }

    @Test("withAlpha returns new color")
    func withAlpha() {
        let c = Color.red.withAlpha(0.5)
        #expect(c.r == 1.0)
        #expect(c.a == 0.5)
    }

    @Test("lerp between colors")
    func lerpColors() {
        let a = Color.black
        let b = Color.white
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.r - 0.5) < 0.001)
        #expect(abs(mid.g - 0.5) < 0.001)
        #expect(abs(mid.b - 0.5) < 0.001)
    }

    @Test("named colors are correct")
    func namedColors() {
        #expect(Color.black == Color(gray: 0))
        #expect(Color.white == Color(gray: 1))
        #expect(Color.red == Color(r: 1, g: 0, b: 0))
        #expect(Color.green == Color(r: 0, g: 1, b: 0))
        #expect(Color.blue == Color(r: 0, g: 0, b: 1))
        #expect(Color.clear.a == 0)
    }

    @Test("clearColor conversion")
    func clearColorConversion() {
        let c = Color(r: 0.5, g: 0.25, b: 0.75, a: 1.0)
        let cc = c.clearColor
        #expect(abs(cc.red - 0.5) < 0.001)
        #expect(abs(cc.green - 0.25) < 0.001)
        #expect(abs(cc.blue - 0.75) < 0.001)
    }
}

// MARK: - Noise Tests

@Suite("NoiseGenerator")
struct NoiseTests {

    @Test("1D noise output in 0..1 range")
    func noise1DRange() {
        let gen = NoiseGenerator()
        for i in 0..<100 {
            let x = Float(i) * 0.1
            let v = gen.noise(x)
            #expect(v >= 0 && v <= 1, "noise(\(x)) = \(v) out of range")
        }
    }

    @Test("2D noise output in 0..1 range")
    func noise2DRange() {
        let gen = NoiseGenerator()
        for i in 0..<50 {
            for j in 0..<50 {
                let x = Float(i) * 0.1
                let y = Float(j) * 0.1
                let v = gen.noise(x, y)
                #expect(v >= 0 && v <= 1)
            }
        }
    }

    @Test("3D noise output in 0..1 range")
    func noise3DRange() {
        let gen = NoiseGenerator()
        for i in 0..<20 {
            let x = Float(i) * 0.1
            let v = gen.noise(x, x * 0.7, x * 1.3)
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test("noise is deterministic")
    func noiseDeterministic() {
        let gen = NoiseGenerator()
        let v1 = gen.noise(1.5, 2.3)
        let v2 = gen.noise(1.5, 2.3)
        #expect(v1 == v2)
    }

    @Test("different seeds produce different output")
    func noiseSeedDifference() {
        let gen0 = NoiseGenerator(seed: 0)
        let gen1 = NoiseGenerator(seed: 42)
        // 非整数座標を使う（整数座標ではPerlinノイズは常に0）
        let v0 = gen0.noise(1.3, 2.7)
        let v1 = gen1.noise(1.3, 2.7)
        #expect(v0 != v1)
    }

    @Test("noise varies spatially")
    func noiseSpatialVariation() {
        let gen = NoiseGenerator()
        var values: Set<Int> = []
        for i in 0..<10 {
            // 非整数座標を使う
            let v = gen.noise(Float(i) * 0.73 + 0.1)
            values.insert(Int(v * 1000))
        }
        #expect(values.count > 3, "noise should produce varied output")
    }

    @Test("octaves affect output")
    func noiseOctaves() {
        var gen1 = NoiseGenerator()
        gen1.octaves = 1
        var gen4 = NoiseGenerator()
        gen4.octaves = 4

        // With different octaves, the output should differ at most points
        var diffs = 0
        for i in 0..<20 {
            let x = Float(i) * 0.5
            if abs(gen1.noise(x) - gen4.noise(x)) > 0.001 {
                diffs += 1
            }
        }
        #expect(diffs > 5, "different octave counts should produce different results")
    }
}

// MARK: - MathUtils Tests

@Suite("MathUtils")
struct MathUtilsTests {

    @Test("map linear range")
    func mapLinear() {
        #expect(map(5, 0, 10, 0, 100) == 50)
        #expect(map(0, 0, 10, 100, 200) == 100)
        #expect(map(10, 0, 10, 100, 200) == 200)
    }

    @Test("map with negative ranges")
    func mapNegative() {
        let result = map(0, -10, 10, 0, 100)
        #expect(abs(result - 50) < 0.0001)
    }

    @Test("constrain clamps within range")
    func constrainClamp() {
        #expect(constrain(5, 0, 10) == 5)
        #expect(constrain(-5, 0, 10) == 0)
        #expect(constrain(15, 0, 10) == 10)
    }

    @Test("norm normalizes to 0-1")
    func normRange() {
        #expect(norm(5, 0, 10) == 0.5)
        #expect(norm(0, 0, 10) == 0)
        #expect(norm(10, 0, 10) == 1)
    }

    @Test("dist 2D")
    func dist2D() {
        #expect(dist(0, 0, 3, 4) == 5)
        #expect(dist(0, 0, 0, 0) == 0)
    }

    @Test("dist 3D")
    func dist3D() {
        let d = dist(0, 0, 0, 1, 1, 1)
        #expect(abs(d - sqrt(Float(3))) < 0.0001)
    }

    @Test("sq returns square")
    func sqTest() {
        #expect(sq(3) == 9)
        #expect(sq(-4) == 16)
    }

    @Test("mag 2D")
    func mag2D() {
        #expect(mag(3, 4) == 5)
    }
}

// MARK: - Random Tests

@Suite("Random")
@MainActor
struct RandomTests {

    @Test("random with high returns value in range")
    func randomHighRange() {
        for _ in 0..<100 {
            let v = random(Float(10))
            #expect(v >= 0 && v < 10)
        }
    }

    @Test("random with low and high returns value in range")
    func randomLowHighRange() {
        for _ in 0..<100 {
            let v = random(Float(5), Float(15))
            #expect(v >= 5 && v < 15)
        }
    }

    @Test("randomSeed produces deterministic sequence")
    func randomSeedDeterminism() {
        randomSeed(42)
        let a1 = random(Float(100))
        let a2 = random(Float(100))
        randomSeed(42)
        let b1 = random(Float(100))
        let b2 = random(Float(100))
        #expect(a1 == b1)
        #expect(a2 == b2)
    }
}

// MARK: - Vec2 Tests

@Suite("Vec2 Extensions")
struct Vec2Tests {

    @Test("magnitude")
    func magnitudeTest() {
        let v = Vec2(3, 4)
        #expect(abs(v.magnitude - 5) < 0.0001)
    }

    @Test("magnitudeSquared")
    func magnitudeSquaredTest() {
        let v = Vec2(3, 4)
        #expect(abs(v.magnitudeSquared - 25) < 0.0001)
    }

    @Test("heading returns correct angle")
    func headingTest() {
        let v = Vec2(1, 0)
        #expect(abs(v.heading()) < 0.0001)
        let v2 = Vec2(0, 1)
        #expect(abs(v2.heading() - Float.pi / 2) < 0.0001)
    }

    @Test("rotated 90 degrees")
    func rotateTest() {
        let v = Vec2(1, 0)
        let r = v.rotated(Float.pi / 2)
        #expect(abs(r.x) < 0.0001)
        #expect(abs(r.y - 1) < 0.0001)
    }

    @Test("limited caps magnitude")
    func limitTest() {
        let v = Vec2(10, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 5) < 0.0001)
    }

    @Test("limited does not affect small vectors")
    func limitSmallTest() {
        let v = Vec2(2, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 2) < 0.0001)
    }

    @Test("normalized returns unit vector")
    func normalizedTest() {
        let v = Vec2(3, 4)
        let n = v.normalized()
        #expect(abs(n.magnitude - 1) < 0.0001)
    }

    @Test("normalized zero vector returns zero")
    func normalizedZeroTest() {
        let v = Vec2(0, 0)
        let n = v.normalized()
        #expect(n == .zero)
    }

    @Test("fromAngle creates correct vector")
    func fromAngleTest() {
        let v = Vec2.fromAngle(0)
        #expect(abs(v.x - 1) < 0.0001)
        #expect(abs(v.y) < 0.0001)
    }

    @Test("random2D has unit magnitude")
    func random2DTest() {
        for _ in 0..<20 {
            let v = Vec2.random2D()
            #expect(abs(v.magnitude - 1) < 0.001)
        }
    }

    @Test("dist to another vector")
    func distToTest() {
        let a = Vec2(0, 0)
        let b = Vec2(3, 4)
        #expect(abs(a.dist(to: b) - 5) < 0.0001)
    }

    @Test("dot product")
    func dotTest() {
        let a = Vec2(1, 0)
        let b = Vec2(0, 1)
        #expect(abs(a.dot(b)) < 0.0001)
    }

    @Test("lerp to another vector")
    func lerpTest() {
        let a = Vec2(0, 0)
        let b = Vec2(10, 10)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 5) < 0.0001)
    }
}

// MARK: - Vec3 Tests

@Suite("Vec3 Extensions")
struct Vec3Tests {

    @Test("magnitude")
    func magnitudeTest() {
        let v = Vec3(1, 2, 2)
        #expect(abs(v.magnitude - 3) < 0.0001)
    }

    @Test("limited caps magnitude")
    func limitTest() {
        let v = Vec3(10, 0, 0)
        let l = v.limited(5)
        #expect(abs(l.magnitude - 5) < 0.0001)
    }

    @Test("normalized returns unit vector")
    func normalizedTest() {
        let v = Vec3(1, 2, 2)
        let n = v.normalized()
        #expect(abs(n.magnitude - 1) < 0.0001)
    }

    @Test("random3D has unit magnitude")
    func random3DTest() {
        for _ in 0..<20 {
            let v = Vec3.random3D()
            #expect(abs(v.magnitude - 1) < 0.01)
        }
    }

    @Test("cross product correctness")
    func crossTest() {
        let x = Vec3(1, 0, 0)
        let y = Vec3(0, 1, 0)
        let z = x.cross(y)
        #expect(abs(z.x) < 0.0001)
        #expect(abs(z.y) < 0.0001)
        #expect(abs(z.z - 1) < 0.0001)
    }

    @Test("dist to another vector")
    func distToTest() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(1, 2, 2)
        #expect(abs(a.dist(to: b) - 3) < 0.0001)
    }

    @Test("lerp to another vector")
    func lerpTest() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(10, 20, 30)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 10) < 0.0001)
        #expect(abs(mid.z - 15) < 0.0001)
    }
}

// MARK: - SIMD2 lerp Tests

@Suite("SIMD2 lerp")
struct SIMD2LerpTests {

    @Test("lerp SIMD2 at boundaries")
    func lerpBoundaries() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(10, 20)
        let start = lerp(a, b, 0)
        let end = lerp(a, b, 1)
        let mid = lerp(a, b, 0.5)
        #expect(start == a)
        #expect(end == b)
        #expect(abs(mid.x - 5) < 0.0001)
        #expect(abs(mid.y - 10) < 0.0001)
    }
}

// MARK: - Easing Tests

@Suite("Easing")
struct EasingTests {

    @Test("polynomial easings have correct boundaries")
    func polynomialBoundaries() {
        let fns: [(Float) -> Float] = [
            easeInQuad, easeOutQuad, easeInOutQuad,
            easeInCubic, easeOutCubic, easeInOutCubic,
            easeInQuart, easeOutQuart, easeInOutQuart,
            easeInQuint, easeOutQuint, easeInOutQuint,
        ]
        for f in fns {
            #expect(abs(f(0) - 0) < 0.0001, "f(0) should be 0")
            #expect(abs(f(1) - 1) < 0.0001, "f(1) should be 1")
        }
    }

    @Test("trigonometric easings have correct boundaries")
    func trigBoundaries() {
        let fns: [(Float) -> Float] = [
            easeInSine, easeOutSine, easeInOutSine,
            easeInCirc, easeOutCirc, easeInOutCirc,
        ]
        for f in fns {
            #expect(abs(f(0) - 0) < 0.0001, "f(0) should be 0")
            #expect(abs(f(1) - 1) < 0.0001, "f(1) should be 1")
        }
    }

    @Test("expo easings have correct boundaries")
    func expoBoundaries() {
        #expect(easeInExpo(0) == 0)
        #expect(abs(easeInExpo(1) - 1) < 0.01)
        #expect(abs(easeOutExpo(0)) < 0.0001)
        #expect(easeOutExpo(1) == 1)
        #expect(easeInOutExpo(0) == 0)
        #expect(easeInOutExpo(1) == 1)
    }

    @Test("back easings have correct boundaries")
    func backBoundaries() {
        #expect(abs(easeInBack(0)) < 0.0001)
        #expect(abs(easeInBack(1) - 1) < 0.0001)
        #expect(abs(easeOutBack(0)) < 0.0001)
        #expect(abs(easeOutBack(1) - 1) < 0.0001)
        #expect(abs(easeInOutBack(0)) < 0.0001)
        #expect(abs(easeInOutBack(1) - 1) < 0.0001)
    }

    @Test("elastic easings have correct boundaries")
    func elasticBoundaries() {
        #expect(easeInElastic(0) == 0)
        #expect(easeInElastic(1) == 1)
        #expect(easeOutElastic(0) == 0)
        #expect(easeOutElastic(1) == 1)
        #expect(easeInOutElastic(0) == 0)
        #expect(easeInOutElastic(1) == 1)
    }

    @Test("bounce easings have correct boundaries")
    func bounceBoundaries() {
        #expect(abs(easeInBounce(0)) < 0.0001)
        #expect(abs(easeInBounce(1) - 1) < 0.0001)
        #expect(abs(easeOutBounce(0)) < 0.0001)
        #expect(abs(easeOutBounce(1) - 1) < 0.0001)
        #expect(abs(easeInOutBounce(0)) < 0.0001)
        #expect(abs(easeInOutBounce(1) - 1) < 0.0001)
    }

    @Test("easeInOut midpoint is approximately 0.5")
    func midpoint() {
        let fns: [(Float) -> Float] = [
            easeInOutQuad, easeInOutCubic, easeInOutQuart, easeInOutQuint,
            easeInOutSine, easeInOutExpo, easeInOutCirc,
        ]
        for f in fns {
            #expect(abs(f(0.5) - 0.5) < 0.01, "easeInOut(0.5) should be ~0.5")
        }
    }

    @Test("easeIn is slower than linear at midpoint")
    func easeInSlower() {
        #expect(easeInQuad(0.5) < 0.5)
        #expect(easeInCubic(0.5) < 0.5)
        #expect(easeInQuart(0.5) < 0.5)
    }

    @Test("easeOut is faster than linear at midpoint")
    func easeOutFaster() {
        #expect(easeOutQuad(0.5) > 0.5)
        #expect(easeOutCubic(0.5) > 0.5)
        #expect(easeOutQuart(0.5) > 0.5)
    }

    @Test("ease convenience interpolates correctly")
    func easeConvenience() {
        let result = ease(0.5, from: 10, to: 20, using: easeInOutQuad)
        #expect(abs(result - 15) < 0.01)
    }
}
