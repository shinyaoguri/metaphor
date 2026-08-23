import simd

// MARK: - Type Aliases

/// A two-dimensional vector, an alias for `SIMD2<Float>`.
public typealias Vec2 = SIMD2<Float>

/// A three-dimensional vector, an alias for `SIMD3<Float>`.
public typealias Vec3 = SIMD3<Float>

// MARK: - SIMD2<Float> Processing-Style Extensions

extension SIMD2 where Scalar == Float {

    /// The length (magnitude) of the vector.
    public var magnitude: Float {
        simd_length(self)
    }

    /// The squared length of the vector, which avoids the cost of a square root.
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// Calculates the angle of the vector in radians, measured from the positive x-axis.
    ///
    /// - Returns: The heading angle in radians.
    public func heading() -> Float {
        atan2(y, x)
    }

    /// Returns a new vector rotated by the given angle.
    ///
    /// - Parameter angle: The rotation angle in radians.
    /// - Returns: The rotated vector.
    public func rotated(_ angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(x * c - y * s, x * s + y * c)
    }

    /// Returns a new vector whose magnitude is clamped to the given maximum.
    ///
    /// - Parameter max: The maximum allowed magnitude.
    /// - Returns: A vector whose length does not exceed `max`.
    public func limited(_ max: Float) -> SIMD2<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// Returns a unit vector pointing in the same direction.
    ///
    /// - Returns: The normalized vector, or the zero vector when the original vector has zero length.
    public func normalized() -> SIMD2<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// Calculates the Euclidean distance to another vector.
    ///
    /// - Parameter other: The target vector.
    /// - Returns: The distance between the two vectors.
    public func dist(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Calculates the dot product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar dot product.
    public func dot(_ other: SIMD2<Float>) -> Float {
        simd_dot(self, other)
    }

    /// Creates a unit vector from the given angle.
    ///
    /// - Parameter angle: The angle in radians.
    /// - Returns: A unit vector pointing in the direction of `angle`.
    public static func fromAngle(_ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle), sin(angle))
    }

    /// Creates a random unit vector with a uniformly distributed direction.
    ///
    /// It uses the shared seeded pseudo-random generator set by ``randomSeed(_:)``, so it
    /// reproduces deterministically once a seed has been set.
    ///
    /// - Returns: A random 2D unit vector.
    @MainActor
    public static func random2D() -> SIMD2<Float> {
        let angle = MetaphorCore.random(0, Float.pi * 2)
        return fromAngle(angle)
    }

    /// Linearly interpolates toward another vector.
    ///
    /// - Parameters:
    ///   - other: The target vector.
    ///   - t: The interpolation factor, normally in the range 0...1.
    /// - Returns: The interpolated vector.
    public func lerp(to other: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        self + (other - self) * t
    }

    /// Returns a new vector with the given magnitude, preserving the direction.
    ///
    /// - Parameter len: The target magnitude.
    /// - Returns: A vector with the same direction and the given length.
    public func withMagnitude(_ len: Float) -> SIMD2<Float> {
        normalized() * len
    }

    /// Calculates the 2D cross product, which corresponds to the z component of the 3D cross product.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar cross product value.
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }

    /// Calculates the signed angle in radians between this vector and another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The angle between the two vectors in radians.
    public func angleBetween(_ other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }

    // MARK: Mutating (Processing PVector スタイル)

    /// Makes this vector a unit vector in place (the mutating form of ``normalized()``).
    ///
    /// When the length is zero, it stays the zero vector and does not change.
    public mutating func normalize() {
        self = normalized()
    }

    /// Clamps this vector's magnitude to a maximum in place (the mutating form of ``limited(_:)``).
    ///
    /// - Parameter max: The maximum allowed magnitude.
    public mutating func limit(_ max: Float) {
        self = limited(max)
    }

    /// Rotates this vector in place (the mutating form of ``rotated(_:)``).
    ///
    /// - Parameter angle: The rotation angle in radians.
    public mutating func rotate(_ angle: Float) {
        self = rotated(angle)
    }

    /// Sets this vector's magnitude in place, preserving the direction
    /// (the mutating form of ``withMagnitude(_:)``; the equivalent of Processing's `setMag()`).
    ///
    /// When the length is zero, it stays the zero vector and does not change.
    ///
    /// - Parameter len: The target magnitude.
    public mutating func setMag(_ len: Float) {
        self = withMagnitude(len)
    }
}

// MARK: - SIMD3<Float> Processing-Style Extensions

extension SIMD3 where Scalar == Float {

    /// The length (magnitude) of the vector.
    public var magnitude: Float {
        simd_length(self)
    }

    /// The squared length of the vector, which avoids the cost of a square root.
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// Returns a new vector whose magnitude is clamped to the given maximum.
    ///
    /// - Parameter max: The maximum allowed magnitude.
    /// - Returns: A vector whose length does not exceed `max`.
    public func limited(_ max: Float) -> SIMD3<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// Returns a unit vector pointing in the same direction.
    ///
    /// - Returns: The normalized vector, or the zero vector when the original vector has zero length.
    public func normalized() -> SIMD3<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// Calculates the Euclidean distance to another vector.
    ///
    /// - Parameter other: The target vector.
    /// - Returns: The distance between the two vectors.
    public func dist(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Calculates the dot product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar dot product.
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    /// Calculates the cross product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: A vector perpendicular to both input vectors.
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// Creates a random unit vector distributed uniformly over the surface of the unit sphere.
    ///
    /// It uses the Marsaglia rejection method to produce a uniform distribution.
    /// It uses the shared seeded pseudo-random generator set by ``randomSeed(_:)``, so it
    /// reproduces deterministically once a seed has been set.
    ///
    /// - Returns: A random 3D unit vector.
    @MainActor
    public static func random3D() -> SIMD3<Float> {
        // Marsaglia 法
        var v: SIMD3<Float>
        repeat {
            v = SIMD3(
                MetaphorCore.random(-1, 1),
                MetaphorCore.random(-1, 1),
                MetaphorCore.random(-1, 1)
            )
        } while simd_length_squared(v) > 1 || simd_length_squared(v) < 0.0001
        return simd_normalize(v)
    }

    /// Linearly interpolates toward another vector.
    ///
    /// - Parameters:
    ///   - other: The target vector.
    ///   - t: The interpolation factor, normally in the range 0...1.
    /// - Returns: The interpolated vector.
    public func lerp(to other: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        self + (other - self) * t
    }

    /// Returns a new vector with the given magnitude, preserving the direction.
    ///
    /// - Parameter len: The target magnitude.
    /// - Returns: A vector with the same direction and the given length.
    public func withMagnitude(_ len: Float) -> SIMD3<Float> {
        normalized() * len
    }

    /// Calculates the unsigned angle in radians between this vector and another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The angle between the two vectors in radians, in the range 0...pi.
    public func angleBetween(_ other: SIMD3<Float>) -> Float {
        let d = dot(other)
        let m = magnitude * other.magnitude
        guard m > 0 else { return 0 }
        return acos(Swift.min(Swift.max(d / m, -1), 1))
    }

    // MARK: Mutating (Processing PVector スタイル)

    /// Makes this vector a unit vector in place (the mutating form of ``normalized()``).
    ///
    /// When the length is zero, it stays the zero vector and does not change.
    public mutating func normalize() {
        self = normalized()
    }

    /// Clamps this vector's magnitude to a maximum in place (the mutating form of ``limited(_:)``).
    ///
    /// - Parameter max: The maximum allowed magnitude.
    public mutating func limit(_ max: Float) {
        self = limited(max)
    }

    /// Sets this vector's magnitude in place, preserving the direction
    /// (the mutating form of ``withMagnitude(_:)``; the equivalent of Processing's `setMag()`).
    ///
    /// When the length is zero, it stays the zero vector and does not change.
    ///
    /// - Parameter len: The target magnitude.
    public mutating func setMag(_ len: Float) {
        self = withMagnitude(len)
    }
}
