import simd

// MARK: - Type Aliases

/// `SIMD2<Float>` のエイリアスである2次元ベクトル。
public typealias Vec2 = SIMD2<Float>

/// `SIMD3<Float>` のエイリアスである3次元ベクトル。
public typealias Vec3 = SIMD3<Float>

// MARK: - SIMD2<Float> Processing-Style Extensions

extension SIMD2 where Scalar == Float {

    /// ベクトルの長さ（大きさ）を返します。
    public var magnitude: Float {
        simd_length(self)
    }

    /// 平方根のコストを回避した、ベクトルの長さの二乗を返します。
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// 正のx軸から測定したベクトルの角度をラジアンで計算します。
    ///
    /// - Returns: ラジアン単位の方向角。
    public func heading() -> Float {
        atan2(y, x)
    }

    /// 指定された角度で回転した新しいベクトルを返します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    /// - Returns: 回転されたベクトル。
    public func rotated(_ angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(x * c - y * s, x * s + y * c)
    }

    /// 指定された最大値に大きさをクランプした新しいベクトルを返します。
    ///
    /// - Parameter max: 許容される最大の大きさ。
    /// - Returns: 長さが `max` を超えないベクトル。
    public func limited(_ max: Float) -> SIMD2<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// 同じ方向を向いた単位ベクトルを返します。
    ///
    /// - Returns: 正規化されたベクトル。元のベクトルの長さがゼロの場合はゼロベクトル。
    public func normalized() -> SIMD2<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// 別のベクトルまでのユークリッド距離を計算します。
    ///
    /// - Parameter other: 対象ベクトル。
    /// - Returns: 2つのベクトル間の距離。
    public func dist(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    /// 別のベクトルとの内積を計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: スカラー内積。
    public func dot(_ other: SIMD2<Float>) -> Float {
        simd_dot(self, other)
    }

    /// 指定された角度から単位ベクトルを作成します。
    ///
    /// - Parameter angle: ラジアン単位の角度。
    /// - Returns: `angle` の方向を向いた単位ベクトル。
    public static func fromAngle(_ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle), sin(angle))
    }

    /// 均一に分布した方向を持つランダムな単位ベクトルを作成します。
    ///
    /// - Returns: ランダムな2D単位ベクトル。
    public static func random2D() -> SIMD2<Float> {
        let angle = Float.random(in: 0..<(Float.pi * 2))
        return fromAngle(angle)
    }

    /// 別のベクトルに向かって線形補間を行います。
    ///
    /// - Parameters:
    ///   - other: 目標ベクトル。
    ///   - t: 補間係数。通常 0...1 の範囲。
    /// - Returns: 補間されたベクトル。
    public func lerp(to other: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        self + (other - self) * t
    }

    /// 方向を維持したまま、指定された大きさを持つ新しいベクトルを返します。
    ///
    /// - Parameter len: 目標の大きさ。
    /// - Returns: 同じ方向で指定された長さを持つベクトル。
    public func withMagnitude(_ len: Float) -> SIMD2<Float> {
        normalized() * len
    }

    /// 3D外積のz成分に相当する2D外積を計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: スカラー外積値。
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }

    /// このベクトルと別のベクトルの間の符号付き角度をラジアンで計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: 2つのベクトル間のラジアン単位の角度。
    public func angleBetween(_ other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }
}

// MARK: - SIMD3<Float> Processing-Style Extensions

extension SIMD3 where Scalar == Float {

    /// ベクトルの長さ（大きさ）を返します。
    public var magnitude: Float {
        simd_length(self)
    }

    /// 平方根のコストを回避した、ベクトルの長さの二乗を返します。
    public var magnitudeSquared: Float {
        simd_length_squared(self)
    }

    /// 指定された最大値に大きさをクランプした新しいベクトルを返します。
    ///
    /// - Parameter max: 許容される最大の大きさ。
    /// - Returns: 長さが `max` を超えないベクトル。
    public func limited(_ max: Float) -> SIMD3<Float> {
        let m = simd_length(self)
        if m > max && m > 0 {
            return self * (max / m)
        }
        return self
    }

    /// 同じ方向を向いた単位ベクトルを返します。
    ///
    /// - Returns: 正規化されたベクトル。元のベクトルの長さがゼロの場合はゼロベクトル。
    public func normalized() -> SIMD3<Float> {
        let m = simd_length(self)
        guard m > 0 else { return .zero }
        return self / m
    }

    /// 別のベクトルまでのユークリッド距離を計算します。
    ///
    /// - Parameter other: 対象ベクトル。
    /// - Returns: 2つのベクトル間の距離。
    public func dist(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// 別のベクトルとの内積を計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: スカラー内積。
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    /// 別のベクトルとの外積を計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: 両方の入力ベクトルに垂直なベクトル。
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// 単位球の表面上に均一に分布するランダムな単位ベクトルを作成します。
    ///
    /// 均一な分布を生成するために Marsaglia 棄却法を使用します。
    ///
    /// - Returns: ランダムな3D単位ベクトル。
    public static func random3D() -> SIMD3<Float> {
        // Marsaglia 法
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

    /// 別のベクトルに向かって線形補間を行います。
    ///
    /// - Parameters:
    ///   - other: 目標ベクトル。
    ///   - t: 補間係数。通常 0...1 の範囲。
    /// - Returns: 補間されたベクトル。
    public func lerp(to other: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        self + (other - self) * t
    }

    /// 方向を維持したまま、指定された大きさを持つ新しいベクトルを返します。
    ///
    /// - Parameter len: 目標の大きさ。
    /// - Returns: 同じ方向で指定された長さを持つベクトル。
    public func withMagnitude(_ len: Float) -> SIMD3<Float> {
        normalized() * len
    }

    /// このベクトルと別のベクトルの間の符号なし角度をラジアンで計算します。
    ///
    /// - Parameter other: もう一方のベクトル。
    /// - Returns: 2つのベクトル間のラジアン単位の角度。0...pi の範囲。
    public func angleBetween(_ other: SIMD3<Float>) -> Float {
        let d = dot(other)
        let m = magnitude * other.magnitude
        guard m > 0 else { return 0 }
        return acos(Swift.min(Swift.max(d / m, -1), 1))
    }
}
