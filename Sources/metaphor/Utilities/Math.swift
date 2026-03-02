import Foundation
import simd

// MARK: - float4x4 Extensions

extension float4x4 {
    /// 単位行列
    public static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    /// X軸回転行列
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

    /// Y軸回転行列
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

    /// Z軸回転行列
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

    /// 平行移動行列
    public init(translation: SIMD3<Float>) {
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    /// スケール行列
    public init(scale: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
    }

    /// 均一スケール行列
    public init(scale: Float) {
        self.init(diagonal: SIMD4<Float>(scale, scale, scale, 1))
    }

    /// ビュー行列（lookAt）
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

    /// 透視投影行列
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

    /// 正射影行列
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

/// 度をラジアンに変換
public func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

/// ラジアンを度に変換
public func degrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

// MARK: - Interpolation

/// 線形補間
public func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    a + (b - a) * t
}

/// SIMD2の線形補間
public func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

/// SIMD3の線形補間
public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// SIMD4の線形補間
public func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    a + (b - a) * t
}

/// 0-1の範囲にクランプ
public func saturate(_ x: Float) -> Float {
    min(max(x, 0), 1)
}

/// smoothstep関数
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = saturate((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

// MARK: - Mapping & Clamping

/// 値を一つの範囲から別の範囲にマッピング（Processing風）
public func map(_ value: Float, _ start1: Float, _ stop1: Float, _ start2: Float, _ stop2: Float) -> Float {
    start2 + (stop2 - start2) * ((value - start1) / (stop1 - start1))
}

/// 値を指定範囲にクランプ（Processing風）
public func constrain(_ value: Float, _ low: Float, _ high: Float) -> Float {
    min(max(value, low), high)
}

/// 値を指定範囲から0〜1に正規化
public func norm(_ value: Float, _ start: Float, _ stop: Float) -> Float {
    (value - start) / (stop - start)
}

// MARK: - Distance & Magnitude

/// 2点間の距離（2D）
public func dist(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    return sqrt(dx * dx + dy * dy)
}

/// 2点間の距離（3D）
public func dist(_ x1: Float, _ y1: Float, _ z1: Float, _ x2: Float, _ y2: Float, _ z2: Float) -> Float {
    let dx = x2 - x1
    let dy = y2 - y1
    let dz = z2 - z1
    return sqrt(dx * dx + dy * dy + dz * dz)
}

/// 値の二乗
public func sq(_ value: Float) -> Float {
    value * value
}

/// 2Dベクトルの長さ
public func mag(_ x: Float, _ y: Float) -> Float {
    sqrt(x * x + y * y)
}

// MARK: - Random

/// シード可能な乱数生成器（LCGベース）
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

/// 0からhighまでのランダムなFloat値を返す
@MainActor
public func random(_ high: Float) -> Float {
    random(0, high)
}

/// lowからhighまでのランダムなFloat値を返す
@MainActor
public func random(_ low: Float, _ high: Float) -> Float {
    if var rng = _seededRNG {
        let result = Float.random(in: low..<high, using: &rng)
        _seededRNG = rng
        return result
    }
    return Float.random(in: low..<high)
}

/// 乱数のシード値を設定
@MainActor
public func randomSeed(_ seed: UInt64) {
    _seededRNG = SeededRandomNumberGenerator(seed: seed)
}

/// ガウス分布に従うランダム値を返す（Box-Muller変換）
/// - Parameters:
///   - mean: 平均値（デフォルト0）
///   - sd: 標準偏差（デフォルト1）
@MainActor
public func randomGaussian(_ mean: Float = 0, _ sd: Float = 1) -> Float {
    let u1 = random(Float.leastNormalMagnitude, 1.0)
    let u2 = random(0, 1.0)
    let z = sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
    return mean + z * sd
}

// MARK: - Bezier Math

/// 3次ベジェ曲線上の点を返す
public func bezierPoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
}

/// 3次ベジェ曲線の接線を返す
public func bezierTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let u = 1 - t
    return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
}

// MARK: - Catmull-Rom Curve Math

/// Catmull-Romスプライン上の点を返す
public func curvePoint(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    let t3 = t2 * t
    return 0.5 * ((2 * b) +
                   (-a + c) * t +
                   (2 * a - 5 * b + 4 * c - d) * t2 +
                   (-a + 3 * b - 3 * c + d) * t3)
}

/// Catmull-Romスプラインの接線を返す
public func curveTangent(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let t2 = t * t
    return 0.5 * ((-a + c) +
                   (4 * a - 10 * b + 8 * c - 2 * d) * t +
                   (-3 * a + 9 * b - 9 * c + 3 * d) * t2)
}
