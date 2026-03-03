import simd

// MARK: - Type Aliases

/// A two-dimensional vector, aliasing `SIMD2<Float>`.
public typealias Vec2 = SIMD2<Float>

/// A three-dimensional vector, aliasing `SIMD3<Float>`.
public typealias Vec3 = SIMD3<Float>

// MARK: - SIMD2<Float> Processing-Style Extensions

extension SIMD2 where Scalar == Float {

    /// Returns the length (magnitude) of the vector.
    public var magnitude: Float {
        simd_length(self)
    }

    /// Returns the squared length of the vector, avoiding the cost of a square root.
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// Computes the angle of the vector in radians, measured from the positive x-axis.
    ///
    /// - Returns: The heading angle in radians.
    public func heading() -> Float {
        atan2(y, x)
    }

    /// Returns a new vector rotated by the specified angle.
    ///
    /// - Parameter angle: The rotation angle in radians.
    /// - Returns: The rotated vector.
    public func rotated(_ angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(x * c - y * s, x * s + y * c)
    }

    /// Returns a new vector with its magnitude clamped to the specified maximum.
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
    /// - Returns: The normalized vector, or zero if the original vector has zero length.
    public func normalized() -> SIMD2<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// Computes the Euclidean distance to another vector.
    ///
    /// - Parameter other: The target vector.
    /// - Returns: The distance between the two vectors.
    public func dist(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Computes the dot product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar dot product.
    public func dot(_ other: SIMD2<Float>) -> Float {
        simd_dot(self, other)
    }

    /// Creates a unit vector from the specified angle.
    ///
    /// - Parameter angle: The angle in radians.
    /// - Returns: A unit vector pointing in the direction of `angle`.
    public static func fromAngle(_ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle), sin(angle))
    }

    /// Creates a random unit vector with a uniformly distributed direction.
    ///
    /// - Returns: A random 2D unit vector.
    public static func random2D() -> SIMD2<Float> {
        let angle = Float.random(in: 0..<(Float.pi * 2))
        return fromAngle(angle)
    }

    /// Performs linear interpolation toward another vector.
    ///
    /// - Parameters:
    ///   - other: The target vector.
    ///   - t: The interpolation factor, typically in the range 0...1.
    /// - Returns: The interpolated vector.
    public func lerp(to other: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        self + (other - self) * t
    }

    /// Returns a new vector with the specified magnitude, preserving direction.
    ///
    /// - Parameter len: The desired magnitude.
    /// - Returns: A vector with the given length pointing in the same direction.
    public func withMagnitude(_ len: Float) -> SIMD2<Float> {
        normalized() * len
    }

    /// Computes the 2D cross product, equivalent to the z-component of a 3D cross product.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar cross product value.
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }

    /// Computes the signed angle between this vector and another, in radians.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The angle in radians between the two vectors.
    public func angleBetween(_ other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }
}

// MARK: - SIMD3<Float> Processing-Style Extensions

extension SIMD3 where Scalar == Float {

    /// Returns the length (magnitude) of the vector.
    public var magnitude: Float {
        simd_length(self)
    }

    /// Returns the squared length of the vector, avoiding the cost of a square root.
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// Returns a new vector with its magnitude clamped to the specified maximum.
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
    /// - Returns: The normalized vector, or zero if the original vector has zero length.
    public func normalized() -> SIMD3<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// Computes the Euclidean distance to another vector.
    ///
    /// - Parameter other: The target vector.
    /// - Returns: The distance between the two vectors.
    public func dist(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Computes the dot product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The scalar dot product.
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    /// Computes the cross product with another vector.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: A vector perpendicular to both input vectors.
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// Creates a random unit vector uniformly distributed on the surface of a unit sphere.
    ///
    /// Uses the Marsaglia rejection method to produce a uniform distribution.
    ///
    /// - Returns: A random 3D unit vector.
    public static func random3D() -> SIMD3<Float> {
        // Marsaglia method
        var v: SIMD3<Float>
        repeat {
            v = SIMD3(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
        } while simd_length_squared(v) > 1 || simd_length_squared(v) < 0.0001
        return simd_normalize(v)
    }

    /// Performs linear interpolation toward another vector.
    ///
    /// - Parameters:
    ///   - other: The target vector.
    ///   - t: The interpolation factor, typically in the range 0...1.
    /// - Returns: The interpolated vector.
    public func lerp(to other: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        self + (other - self) * t
    }

    /// Returns a new vector with the specified magnitude, preserving direction.
    ///
    /// - Parameter len: The desired magnitude.
    /// - Returns: A vector with the given length pointing in the same direction.
    public func withMagnitude(_ len: Float) -> SIMD3<Float> {
        normalized() * len
    }

    /// Computes the unsigned angle between this vector and another, in radians.
    ///
    /// - Parameter other: The other vector.
    /// - Returns: The angle in radians between the two vectors, in the range 0...pi.
    public func angleBetween(_ other: SIMD3<Float>) -> Float {
        let d = dot(other)
        let m = magnitude * other.magnitude
        guard m > 0 else { return 0 }
        return acos(Swift.min(Swift.max(d / m, -1), 1))
    }
}
