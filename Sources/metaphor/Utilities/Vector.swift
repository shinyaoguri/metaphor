import simd

// MARK: - Type Aliases

/// 2Dベクトル（SIMD2<Float>のエイリアス）
public typealias Vec2 = SIMD2<Float>

/// 3Dベクトル（SIMD3<Float>のエイリアス）
public typealias Vec3 = SIMD3<Float>

// MARK: - SIMD2<Float> Processing風拡張

extension SIMD2 where Scalar == Float {

    /// ベクトルの長さ
    public var magnitude: Float {
        simd_length(self)
    }

    /// ベクトルの長さの二乗（sqrt不要で高速）
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// ベクトルの角度（ラジアン）
    public func heading() -> Float {
        atan2(y, x)
    }

    /// 指定角度だけ回転した新しいベクトルを返す
    public func rotated(_ angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(x * c - y * s, x * s + y * c)
    }

    /// 長さを最大値に制限した新しいベクトルを返す
    public func limited(_ max: Float) -> SIMD2<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// 正規化（単位ベクトル化）した新しいベクトルを返す
    public func normalized() -> SIMD2<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// 他のベクトルとの距離
    public func dist(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    /// 内積
    public func dot(_ other: SIMD2<Float>) -> Float {
        simd_dot(self, other)
    }

    /// 角度から単位ベクトルを生成
    public static func fromAngle(_ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle), sin(angle))
    }

    /// ランダムな方向の単位ベクトルを生成
    public static func random2D() -> SIMD2<Float> {
        let angle = Float.random(in: 0..<(Float.pi * 2))
        return fromAngle(angle)
    }

    /// 他のベクトルへの線形補間
    public func lerp(to other: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        self + (other - self) * t
    }

    /// 指定した長さに設定した新しいベクトルを返す
    public func withMagnitude(_ len: Float) -> SIMD2<Float> {
        normalized() * len
    }

    /// 2D外積（3D外積のz成分に相当）
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }

    /// 2つのベクトル間の角度（ラジアン）
    public func angleBetween(_ other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }
}

// MARK: - SIMD3<Float> Processing風拡張

extension SIMD3 where Scalar == Float {

    /// ベクトルの長さ
    public var magnitude: Float {
        simd_length(self)
    }

    /// ベクトルの長さの二乗（sqrt不要で高速）
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// 長さを最大値に制限した新しいベクトルを返す
    public func limited(_ max: Float) -> SIMD3<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// 正規化（単位ベクトル化）した新しいベクトルを返す
    public func normalized() -> SIMD3<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// 他のベクトルとの距離
    public func dist(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// 内積
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    /// 外積
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// ランダムな方向の単位ベクトルを生成（3D球面上に均一分布）
    public static func random3D() -> SIMD3<Float> {
        // Marsaglia法
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

    /// 他のベクトルへの線形補間
    public func lerp(to other: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        self + (other - self) * t
    }

    /// 指定した長さに設定した新しいベクトルを返す
    public func withMagnitude(_ len: Float) -> SIMD3<Float> {
        normalized() * len
    }

    /// 2つのベクトル間の角度（ラジアン）
    public func angleBetween(_ other: SIMD3<Float>) -> Float {
        let d = dot(other)
        let m = magnitude * other.magnitude
        guard m > 0 else { return 0 }
        return acos(Swift.min(Swift.max(d / m, -1), 1))
    }
}
