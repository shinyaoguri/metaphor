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
