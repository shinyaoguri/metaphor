import Foundation
import simd

// MARK: - float4x4 Extensions

extension float4x4 {
    /// Creates the identity matrix.
    public static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    /// Creates a rotation matrix around the X axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Creates a rotation matrix around the Y axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Creates a rotation matrix around the Z axis.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
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
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    /// Creates a non-uniform scale matrix.
    ///
    /// - Parameter scale: The scale factors for each axis.
    public init(scale: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
    }

    /// Creates a uniform scale matrix.
    ///
    /// - Parameter scale: The uniform scale factor applied to all axes.
    public init(scale: Float) {
        self.init(diagonal: SIMD4<Float>(scale, scale, scale, 1))
    }

    /// Creates a view matrix using the look-at convention.
    ///
    /// - Parameters:
    ///   - eye: The position of the camera.
    ///   - center: The point the camera is looking at.
    ///   - up: The up direction vector.
    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        self.init(columns: (
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
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public init(perspectiveFov fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        self.init(columns: (
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
    ///   - near: The near clipping plane distance.
    ///   - far: The far clipping plane distance.
    public init(orthographic left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (near - far)
        let tx = (left + right) / (left - right)
        let ty = (top + bottom) / (bottom - top)
        let tz = near / (near - far)

        self.init(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        ))
    }
}

// MARK: - Angle Conversions

/// Converts degrees to radians.
///
/// - Parameter degrees: The angle in degrees.
/// - Returns: The angle in radians.
public func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

/// Converts radians to degrees.
///
/// - Parameter radians: The angle in radians.
/// - Returns: The angle in degrees.
public func degrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

// MARK: - Interpolation

/// Performs linear interpolation between two values.
///
/// - Parameters:
///   - a: The start value.
///   - b: The end value.
///   - t: The interpolation factor, typically in the range [0, 1].
/// - Returns: The interpolated value.
public func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    a + (b - a) * t
}

/// Performs linear interpolation between two 2D vectors.
///
/// - Parameters:
///   - a: The start vector.
///   - b: The end vector.
///   - t: The interpolation factor, typically in the range [0, 1].
/// - Returns: The interpolated vector.
public func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

/// Performs linear interpolation between two 3D vectors.
///
/// - Parameters:
///   - a: The start vector.
///   - b: The end vector.
///   - t: The interpolation factor, typically in the range [0, 1].
/// - Returns: The interpolated vector.
public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// Performs linear interpolation between two 4D vectors.
///
/// - Parameters:
///   - a: The start vector.
///   - b: The end vector.
///   - t: The interpolation factor, typically in the range [0, 1].
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
/// Returns 0 if `x` is less than `edge0`, 1 if `x` is greater than `edge1`,
/// and a smooth Hermite interpolation between 0 and 1 otherwise.
///
/// - Parameters:
///   - edge0: The lower edge of the transition.
///   - edge1: The upper edge of the transition.
///   - x: The input value.
/// - Returns: The smoothly interpolated value in [0, 1].
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = saturate((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

// MARK: - Mapping & Clamping

/// Remaps a value from one range to another.
///
/// - Parameters:
///   - value: The incoming value to remap.
///   - start1: The lower bound of the source range.
///   - stop1: The upper bound of the source range.
///   - start2: The lower bound of the target range.
///   - stop2: The upper bound of the target range.
/// - Returns: The remapped value.
public func map(_ value: Float, _ start1: Float, _ stop1: Float, _ start2: Float, _ stop2: Float) -> Float {
    start2 + (stop2 - start2) * ((value - start1) / (stop1 - start1))
}

/// Constrains a value to the specified range.
///
/// - Parameters:
///   - value: The value to constrain.
///   - low: The minimum allowed value.
///   - high: The maximum allowed value.
/// - Returns: The constrained value.
public func constrain(_ value: Float, _ low: Float, _ high: Float) -> Float {
    min(max(value, low), high)
}

/// Normalizes a value from a given range to the range [0, 1].
///
/// - Parameters:
///   - value: The value to normalize.
///   - start: The lower bound of the source range.
///   - stop: The upper bound of the source range.
/// - Returns: The normalized value.
public func norm(_ value: Float, _ start: Float, _ stop: Float) -> Float {
    (value - start) / (stop - start)
}

// MARK: - Distance & Magnitude

/// Computes the Euclidean distance between two 2D points.
///
/// - Parameters:
///   - x1: The x-coordinate of the first point.
///   - y1: The y-coordinate of the first point.
///   - x2: The x-coordinate of the second point.
///   - y2: The y-coordinate of the second point.
/// - Returns: The distance between the two points.
public func dist(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    return sqrt(dx * dx + dy * dy)
}

/// Computes the Euclidean distance between two 3D points.
///
/// - Parameters:
///   - x1: The x-coordinate of the first point.
///   - y1: The y-coordinate of the first point.
///   - z1: The z-coordinate of the first point.
///   - x2: The x-coordinate of the second point.
///   - y2: The y-coordinate of the second point.
///   - z2: The z-coordinate of the second point.
/// - Returns: The distance between the two points.
public func dist(_ x1: Float, _ y1: Float, _ z1: Float, _ x2: Float, _ y2: Float, _ z2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    let dz = z2 - z1
    return sqrt(dx * dx + dy * dy + dz * dz)
}

/// Computes the square of a value.
///
/// - Parameter value: The value to square.
/// - Returns: The squared value.
public func sq(_ value: Float) -> Float {
    value * value
}

/// Computes the magnitude of a 2D vector.
///
/// - Parameters:
///   - x: The x-component of the vector.
///   - y: The y-component of the vector.
/// - Returns: The magnitude (length) of the vector.
public func mag(_ x: Float, _ y: Float) -> Float {
    sqrt(x * x + y * y)
}

/// Computes the magnitude of a 3D vector.
///
/// - Parameters:
///   - x: The x-component of the vector.
///   - y: The y-component of the vector.
///   - z: The z-component of the vector.
/// - Returns: The magnitude (length) of the vector.
public func mag(_ x: Float, _ y: Float, _ z: Float) -> Float {
    sqrt(x * x + y * y + z * z)
}

// MARK: - Random

/// Provides a seedable random number generator based on a linear congruential generator.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@MainActor
private var _seededRNG: SeededRandomNumberGenerator?

/// Returns a random float value from 0 up to (but not including) the specified upper bound.
///
/// - Parameter high: The exclusive upper bound.
/// - Returns: A random float in the range [0, `high`).
@MainActor
public func random(_ high: Float) -> Float {
    random(0, high)
}

/// Returns a random float value within the specified range.
///
/// - Parameters:
///   - low: The inclusive lower bound.
///   - high: The exclusive upper bound.
/// - Returns: A random float in the range [`low`, `high`).
@MainActor
public func random(_ low: Float, _ high: Float) -> Float {
    if var rng = _seededRNG {
        let result = Float.random(in: low..<high, using: &rng)
        _seededRNG = rng
        return result
    }
    return Float.random(in: low..<high)
}

/// Sets the seed for the random number generator.
///
/// Subsequent calls to ``random(_:)`` and ``random(_:_:)`` will use this seed
/// to produce a deterministic sequence.
///
/// - Parameter seed: The seed value.
@MainActor
public func randomSeed(_ seed: UInt64) {
    _seededRNG = SeededRandomNumberGenerator(seed: seed)
}

/// Returns a random value following a Gaussian (normal) distribution using the Box-Muller transform.
///
/// - Parameters:
///   - mean: The mean of the distribution (default is 0).
///   - sd: The standard deviation of the distribution (default is 1).
/// - Returns: A random float drawn from the specified Gaussian distribution.
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
///   - a: The first control point (start).
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point (end).
///   - t: The parameter along the curve, typically in [0, 1].
/// - Returns: The value on the Bezier curve at parameter `t`.
public func bezierPoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
}

/// Evaluates the tangent of a cubic Bezier curve at the given parameter.
///
/// - Parameters:
///   - a: The first control point (start).
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point (end).
///   - t: The parameter along the curve, typically in [0, 1].
/// - Returns: The tangent value of the Bezier curve at parameter `t`.
public func bezierTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
}

// MARK: - Catmull-Rom Curve Math

/// Evaluates a point on a Catmull-Rom spline at the given parameter.
///
/// - Parameters:
///   - a: The first control point.
///   - b: The second control point (curve passes through here at `t = 0`).
///   - c: The third control point (curve passes through here at `t = 1`).
///   - d: The fourth control point.
///   - t: The parameter along the spline, typically in [0, 1].
/// - Returns: The value on the Catmull-Rom spline at parameter `t`.
public func curvePoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    let t3 = t2 * t
    return 0.5 * ((2 * b) +
                   (-a + c) * t +
                   (2 * a - 5 * b + 4 * c - d) * t2 +
                   (-a + 3 * b - 3 * c + d) * t3)
}

/// Evaluates the tangent of a Catmull-Rom spline at the given parameter.
///
/// - Parameters:
///   - a: The first control point.
///   - b: The second control point.
///   - c: The third control point.
///   - d: The fourth control point.
///   - t: The parameter along the spline, typically in [0, 1].
/// - Returns: The tangent value of the Catmull-Rom spline at parameter `t`.
public func curveTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    return 0.5 * ((-a + c) +
                   (4 * a - 10 * b + 8 * c - 2 * d) * t +
                   (-3 * a + 9 * b - 9 * c + 3 * d) * t2)
}
