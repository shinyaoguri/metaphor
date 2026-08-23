import Foundation
import simd

// MARK: - float4x4 Extensions

extension float4x4 {
    /// The identity matrix.
    public static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    /// Creates a rotation matrix around the x-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            columns: (
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, c, s, 0),
                SIMD4<Float>(0, -s, c, 0),
                SIMD4<Float>(0, 0, 0, 1)
            ))
    }

    /// Creates a rotation matrix around the y-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            columns: (
                SIMD4<Float>(c, 0, -s, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(s, 0, c, 0),
                SIMD4<Float>(0, 0, 0, 1)
            ))
    }

    /// Creates a rotation matrix around the z-axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            columns: (
                SIMD4<Float>(c, s, 0, 0),
                SIMD4<Float>(-s, c, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(0, 0, 0, 1)
            ))
    }

    /// Creates a translation matrix from a 3D vector.
    ///
    /// - Parameter translation: The translation offset along each axis.
    public init(translation: SIMD3<Float>) {
        self.init(
            columns: (
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(translation.x, translation.y, translation.z, 1)
            ))
    }

    /// Creates a non-uniform scale matrix.
    ///
    /// - Parameter scale: The scale factor for each axis.
    public init(scale: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
    }

    /// Creates a uniform scale matrix.
    ///
    /// - Parameter scale: The uniform scale factor applied to every axis.
    public init(scale: Float) {
        self.init(diagonal: SIMD4<Float>(scale, scale, scale, 1))
    }

    /// Creates a look-at view matrix.
    ///
    /// - Parameters:
    ///   - eye: The position of the camera.
    ///   - center: The point the camera looks at.
    ///   - up: The up direction vector.
    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        // eye == center では視線方向が定義できないため +Z を採用（NaN 行列を防止）
        let forward = eye - center
        let z = simd_length_squared(forward) > 0 ? normalize(forward) : SIMD3<Float>(0, 0, 1)
        // up と視線が平行だと外積がゼロベクトルになり normalize が NaN を返すため
        // 代替の up 軸を選ぶ
        var xRaw = cross(up, z)
        if simd_length_squared(xRaw) < 1e-12 {
            let altUp: SIMD3<Float> = abs(z.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            xRaw = cross(altUp, z)
        }
        let x = normalize(xRaw)
        let y = cross(z, x)

        self.init(
            columns: (
                SIMD4<Float>(x.x, y.x, z.x, 0),
                SIMD4<Float>(x.y, y.y, z.y, 0),
                SIMD4<Float>(x.z, y.z, z.z, 0),
                SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
            ))
    }

    /// Creates a perspective projection matrix.
    ///
    /// - Parameters:
    ///   - fov: The vertical field of view in radians.
    ///   - aspect: The aspect ratio (width / height).
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    public init(perspectiveFov fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        self.init(
            columns: (
                SIMD4<Float>(x, 0, 0, 0),
                SIMD4<Float>(0, y, 0, 0),
                SIMD4<Float>(0, 0, z, -1),
                SIMD4<Float>(0, 0, z * near, 0)
            ))
    }

    /// Creates an orthographic projection matrix.
    ///
    /// - Parameters:
    ///   - left: The left edge of the view volume.
    ///   - right: The right edge of the view volume.
    ///   - bottom: The bottom edge of the view volume.
    ///   - top: The top edge of the view volume.
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    public init(
        orthographic left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float
    ) {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (near - far)
        let tx = (left + right) / (left - right)
        let ty = (top + bottom) / (bottom - top)
        let tz = near / (near - far)

        self.init(
            columns: (
                SIMD4<Float>(sx, 0, 0, 0),
                SIMD4<Float>(0, sy, 0, 0),
                SIMD4<Float>(0, 0, sz, 0),
                SIMD4<Float>(tx, ty, tz, 1)
            ))
    }
}

// MARK: - Angle Conversions

/// Converts an angle in degrees to radians.
///
/// - Parameter degrees: The angle in degrees.
/// - Returns: The angle in radians.
public func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

/// Converts an angle in radians to degrees.
///
/// - Parameter radians: The angle in radians.
/// - Returns: The angle in degrees.
public func degrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

// MARK: - Interpolation

/// Linearly interpolates between two values.
///
/// - Parameters:
///   - a: The starting value.
///   - b: The ending value.
///   - t: The interpolation factor, normally in the range [0, 1].
/// - Returns: The interpolated value.
public func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    a + (b - a) * t
}

/// Linearly interpolates between two 2D vectors.
///
/// - Parameters:
///   - a: The starting vector.
///   - b: The ending vector.
///   - t: The interpolation factor, normally in the range [0, 1].
/// - Returns: The interpolated vector.
public func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

/// Linearly interpolates between two 3D vectors.
///
/// - Parameters:
///   - a: The starting vector.
///   - b: The ending vector.
///   - t: The interpolation factor, normally in the range [0, 1].
/// - Returns: The interpolated vector.
public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// Linearly interpolates between two 4D vectors.
///
/// - Parameters:
///   - a: The starting vector.
///   - b: The ending vector.
///   - t: The interpolation factor, normally in the range [0, 1].
/// - Returns: The interpolated vector.
public func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    a + (b - a) * t
}

/// Clamps a value to the range [0, 1].
///
/// - Parameter x: The value to clamp.
/// - Returns: The clamped value.
public func saturate(_ x: Float) -> Float {
    min(max(x, 0), 1)
}

/// Performs Hermite interpolation between two edges.
///
/// Returns 0 when `x` is less than `edge0` and 1 when it is greater than `edge1`;
/// otherwise it returns a smooth Hermite interpolation between 0 and 1.
///
/// - Parameters:
///   - edge0: The lower edge of the transition.
///   - edge1: The upper edge of the transition.
///   - x: The input value.
/// - Returns: A value smoothly interpolated within the range [0, 1].
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = saturate((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

// MARK: - Mapping & Clamping

/// Re-maps a value from one range to another.
///
/// - Parameters:
///   - value: The input value to re-map.
///   - start1: The lower bound of the value's current range.
///   - stop1: The upper bound of the value's current range.
///   - start2: The lower bound of the value's target range.
///   - stop2: The upper bound of the value's target range.
/// - Returns: The re-mapped value. When the current range has zero width
///   (`start1 == stop1`), returns `start2` to avoid propagating NaN or infinity.
public func map(_ value: Float, _ start1: Float, _ stop1: Float, _ start2: Float, _ stop2: Float)
    -> Float
{
    let range = stop1 - start1
    guard range != 0 else { return start2 }
    return start2 + (stop2 - start2) * ((value - start1) / range)
}

/// Constrains a value to the given range.
///
/// - Parameters:
///   - value: The value to constrain.
///   - low: The minimum allowed value.
///   - high: The maximum allowed value.
/// - Returns: The constrained value.
public func constrain(_ value: Float, _ low: Float, _ high: Float) -> Float {
    min(max(value, low), high)
}

/// Normalizes a value from the given range into the range [0, 1].
///
/// - Parameters:
///   - value: The value to normalize.
///   - start: The lower bound of the value's current range.
///   - stop: The upper bound of the value's current range.
/// - Returns: The normalized value. When the range has zero width (`start == stop`),
///   returns 0 to avoid propagating NaN or infinity.
public func norm(_ value: Float, _ start: Float, _ stop: Float) -> Float {
    let range = stop - start
    guard range != 0 else { return 0 }
    return (value - start) / range
}

// MARK: - Distance & Magnitude

/// Calculates the Euclidean distance between two 2D points.
///
/// - Parameters:
///   - x1: The x coordinate of the first point.
///   - y1: The y coordinate of the first point.
///   - x2: The x coordinate of the second point.
///   - y2: The y coordinate of the second point.
/// - Returns: The distance between the two points.
public func dist(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    return sqrt(dx * dx + dy * dy)
}

/// Calculates the Euclidean distance between two 3D points.
///
/// - Parameters:
///   - x1: The x coordinate of the first point.
///   - y1: The y coordinate of the first point.
///   - z1: The z coordinate of the first point.
///   - x2: The x coordinate of the second point.
///   - y2: The y coordinate of the second point.
///   - z2: The z coordinate of the second point.
/// - Returns: The distance between the two points.
public func dist(_ x1: Float, _ y1: Float, _ z1: Float, _ x2: Float, _ y2: Float, _ z2: Float)
    -> Float
{
    let dx = x2 - x1
    let dy = y2 - y1
    let dz = z2 - z1
    return sqrt(dx * dx + dy * dy + dz * dz)
}

/// Calculates the square of a value.
///
/// - Parameter value: The value to square.
/// - Returns: The squared value.
public func sq(_ value: Float) -> Float {
    value * value
}

/// Calculates the magnitude of a 2D vector.
///
/// - Parameters:
///   - x: The x component of the vector.
///   - y: The y component of the vector.
/// - Returns: The magnitude (length) of the vector.
public func mag(_ x: Float, _ y: Float) -> Float {
    sqrt(x * x + y * y)
}

/// Calculates the magnitude of a 3D vector.
///
/// - Parameters:
///   - x: The x component of the vector.
///   - y: The y component of the vector.
///   - z: The z component of the vector.
/// - Returns: The magnitude (length) of the vector.
public func mag(_ x: Float, _ y: Float, _ z: Float) -> Float {
    sqrt(x * x + y * y + z * z)
}

// MARK: - Random

/// A seedable pseudo-random number generator based on a linear congruential generator.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@MainActor
private var _seededRNG: SeededRandomNumberGenerator?

/// Returns a random Float value from 0 up to the given upper bound, which is excluded.
///
/// - Parameter high: The upper bound, which is excluded.
/// - Returns: A random Float value in the range [0, `high`).
@MainActor
public func random(_ high: Float) -> Float {
    random(0, high)
}

/// Returns a random Float value within the given range.
///
/// - Parameters:
///   - low: The lower bound, which is included.
///   - high: The upper bound, which is excluded.
/// - Returns: A random Float value in the range [`low`, `high`).
@MainActor
public func random(_ low: Float, _ high: Float) -> Float {
    let lo = min(low, high)
    let hi = max(low, high)
    guard lo < hi else { return lo }
    if var rng = _seededRNG {
        let result = Float.random(in: lo..<hi, using: &rng)
        _seededRNG = rng
        return result
    }
    return Float.random(in: lo..<hi)
}

/// Sets the seed of the pseudo-random number generator.
///
/// Subsequent calls to ``random(_:)`` and ``random(_:_:)`` use this seed to produce a
/// deterministic sequence of pseudo-random values.
///
/// - Parameter seed: The seed value.
@MainActor
public func randomSeed(_ seed: UInt64) {
    _seededRNG = SeededRandomNumberGenerator(seed: seed)
}

/// Returns a random value from a Gaussian (normal) distribution using the Box-Muller transform.
///
/// - Parameters:
///   - mean: The mean of the distribution (0 by default).
///   - sd: The standard deviation of the distribution (1 by default).
/// - Returns: A random Float value drawn from the given Gaussian distribution.
@MainActor
public func randomGaussian(_ mean: Float = 0, _ sd: Float = 1) -> Float {
    let u1 = random(Float.leastNormalMagnitude, 1.0)
    let u2 = random(0, 1.0)
    let z = sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
    return mean + z * sd
}

// MARK: - Bezier Math

/// Evaluates a point on a cubic Bezier curve at the given parameter.
///
/// - Parameters:
///   - a: The first control point (the start point).
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point (the end point).
///   - t: The parameter along the curve, normally in the range [0, 1].
/// - Returns: The value on the Bezier curve at the parameter `t`.
public func bezierPoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
}

/// Evaluates the tangent of a cubic Bezier curve at the given parameter.
///
/// - Parameters:
///   - a: The first control point (the start point).
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point (the end point).
///   - t: The parameter along the curve, normally in the range [0, 1].
/// - Returns: The tangent value of the Bezier curve at the parameter `t`.
public func bezierTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
}

// MARK: - Catmull-Rom Curve Math

/// Evaluates a point on a Catmull-Rom spline at the given parameter.
///
/// - Parameters:
///   - a: The first control point.
///   - b: The second control point (the spline passes through it at `t = 0`).
///   - c: The third control point (the spline passes through it at `t = 1`).
///   - d: The fourth control point.
///   - t: The parameter along the spline, normally in the range [0, 1].
/// - Returns: The value on the Catmull-Rom spline at the parameter `t`.
public func curvePoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    let t3 = t2 * t
    return 0.5
        * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
}

/// Evaluates a point on a Catmull-Rom spline that reflects `curveTightness`.
///
/// Uses the same basis matrix as Processing's `curveInit()`. `tightness` is a coefficient
/// that changes the basis itself, not a linear blend toward a straight line. When
/// `tightness == 0` the result matches ``curvePoint(_:_:_:_:_:)``, and whatever the value
/// of `tightness`, the spline passes through `b` at `t = 0` and through `c` at `t = 1`.
///
/// - Parameters:
///   - a: The first control point.
///   - b: The second control point (the spline passes through it at `t = 0`).
///   - c: The third control point (the spline passes through it at `t = 1`).
///   - d: The fourth control point.
///   - s: The tightness (0 is the standard Catmull-Rom).
///   - t: The parameter along the spline, normally in the range [0, 1].
/// - Returns: The value on the spline at the parameter `t`.
func curvePoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, tightness s: Float, _ t: Float)
    -> Float
{
    let t2 = t * t
    let t3 = t2 * t
    let k3 = (s - 1) / 2 * a + (s + 3) / 2 * b + (-3 - s) / 2 * c + (1 - s) / 2 * d
    let k2 = (1 - s) * a + (-5 - s) / 2 * b + (s + 2) * c + (s - 1) / 2 * d
    let k1 = (s - 1) / 2 * a + (1 - s) / 2 * c
    return k3 * t3 + k2 * t2 + k1 * t + b
}

/// Evaluates the tangent of a Catmull-Rom spline at the given parameter.
///
/// - Parameters:
///   - a: The first control point.
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point.
///   - t: The parameter along the spline, normally in the range [0, 1].
/// - Returns: The tangent value of the Catmull-Rom spline at the parameter `t`.
public func curveTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    return 0.5
        * ((-a + c) + (4 * a - 10 * b + 8 * c - 2 * d) * t + (-3 * a + 9 * b - 9 * c + 3 * d) * t2)
}
