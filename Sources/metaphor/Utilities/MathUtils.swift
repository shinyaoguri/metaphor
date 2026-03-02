import Foundation

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
