import Foundation

// MARK: - Easing Function Type

/// t を 0..1 から 0..1 にマッピングするイージング関数の型エイリアス。
public typealias EasingFunction = (Float) -> Float

/// イージング関数を使用して2つの値の間を補間します。
/// - Parameters:
///   - t: 0 から 1 の範囲の正規化された時間値。
///   - a: 開始値。
///   - b: 終了値。
///   - f: 補間のカーブを決めるイージング関数。
/// - Returns: a と b の間の補間された値。
public func ease(_ t: Float, from a: Float, to b: Float, using f: EasingFunction) -> Float {
    a + (b - a) * f(t)
}

// MARK: - Quad (Quadratic)

/// ゆっくり始まり加速する2次イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: t の二乗に等しいイージング値。
public func easeInQuad(_ t: Float) -> Float {
    t * t
}

/// 速く始まり減速する2次イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 反転した2次関数によるイージング値。
public func easeOutQuad(_ t: Float) -> Float {
    t * (2 - t)
}

/// 加速してから減速する2次イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的2次関数によるイージング値。
public func easeInOutQuad(_ t: Float) -> Float {
    if t < 0.5 {
        return 2 * t * t
    }
    return -1 + (4 - 2 * t) * t
}

// MARK: - Cubic

/// ゆっくり始まり急激に加速する3次イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: t の三乗に等しいイージング値。
public func easeInCubic(_ t: Float) -> Float {
    t * t * t
}

/// 速く始まり急激に減速する3次イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 反転した3次関数によるイージング値。
public func easeOutCubic(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u + 1
}

/// 滑らかに加速してから減速する3次イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的3次関数によるイージング値。
public func easeInOutCubic(_ t: Float) -> Float {
    if t < 0.5 {
        return 4 * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u + 1
}

// MARK: - Quart (Quartic)

/// 非常にゆっくり始まり急勾配で加速する4次イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: t の四乗に等しいイージング値。
public func easeInQuart(_ t: Float) -> Float {
    t * t * t * t
}

/// 速く始まり急勾配で減速する4次イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 反転した4次関数によるイージング値。
public func easeOutQuart(_ t: Float) -> Float {
    let u = t - 1
    return 1 - u * u * u * u
}

/// 急勾配で加速してから減速する4次イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的4次関数によるイージング値。
public func easeInOutQuart(_ t: Float) -> Float {
    if t < 0.5 {
        return 8 * t * t * t * t
    }
    let u = t - 1
    return 1 - 8 * u * u * u * u
}

// MARK: - Quint (Quintic)

/// 極めてゆっくり始まり強烈に加速する5次イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: t の五乗に等しいイージング値。
public func easeInQuint(_ t: Float) -> Float {
    t * t * t * t * t
}

/// 速く始まり強烈に減速する5次イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 反転した5次関数によるイージング値。
public func easeOutQuint(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u * u * u + 1
}

/// 強烈に加速してから減速する5次イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的5次関数によるイージング値。
public func easeInOutQuint(_ t: Float) -> Float {
    if t < 0.5 {
        return 16 * t * t * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u * u * u + 1
}

// MARK: - Sine

/// コサイン関数を使用してゆっくり始まる正弦波イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: コサイン波の4分の1に基づくイージング値。
public func easeInSine(_ t: Float) -> Float {
    1 - cos(t * Float.pi / 2)
}

/// サイン関数を使用して減速する正弦波イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: サイン波の4分の1に基づくイージング値。
public func easeOutSine(_ t: Float) -> Float {
    sin(t * Float.pi / 2)
}

/// 滑らかに加速・減速する正弦波イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: コサイン波の半分に基づくイージング値。
public func easeInOutSine(_ t: Float) -> Float {
    0.5 * (1 - cos(Float.pi * t))
}

// MARK: - Expo (Exponential)

/// ほぼゼロから指数的に加速する指数イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 2を底とする指数関数による増加のイージング値。
public func easeInExpo(_ t: Float) -> Float {
    t == 0 ? 0 : pow(2, 10 * (t - 1))
}

/// 1に向かって指数的に減速する指数イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 2を底とする指数関数による減衰のイージング値。
public func easeOutExpo(_ t: Float) -> Float {
    t == 1 ? 1 : 1 - pow(2, -10 * t)
}

/// 指数的な加速と減速を持つ指数イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的な2を底とする指数関数によるイージング値。
public func easeInOutExpo(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    if t < 0.5 {
        return 0.5 * pow(2, 20 * t - 10)
    }
    return 1 - 0.5 * pow(2, -20 * t + 10)
}

// MARK: - Circ (Circular)

/// 四分円弧に沿って加速する円形イーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 円形カーブに基づくイージング値。
public func easeInCirc(_ t: Float) -> Float {
    1 - sqrt(1 - t * t)
}

/// 四分円弧に沿って減速する円形イーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 反転した円形カーブに基づくイージング値。
public func easeOutCirc(_ t: Float) -> Float {
    let u = t - 1
    return sqrt(1 - u * u)
}

/// 半円弧に沿った円形イーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 区分的な円形カーブに基づくイージング値。
public func easeInOutCirc(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * (1 - sqrt(1 - 4 * t * t))
    }
    let u = 2 * t - 2
    return 0.5 * (sqrt(1 - u * u) + 1)
}

// MARK: - Back (Overshoot)

private let backS: Float = 1.70158

/// 加速前に引き戻すバックイーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 一時的に 0 を下回ってから 1 に到達するイージング値。
public func easeInBack(_ t: Float) -> Float {
    t * t * ((backS + 1) * t - backS)
}

/// 1 を超えてから元に戻るバックイーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 一時的に 1 を超えてから落ち着くイージング値。
public func easeOutBack(_ t: Float) -> Float {
    let u = t - 1
    return u * u * ((backS + 1) * u + backS) + 1
}

/// 引き戻し、加速、オーバーシュート、収束を行うバックイーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 両端でオーバーシュートするイージング値。
public func easeInOutBack(_ t: Float) -> Float {
    let s = backS * 1.525
    if t < 0.5 {
        let u = 2 * t
        return 0.5 * (u * u * ((s + 1) * u - s))
    }
    let u = 2 * t - 2
    return 0.5 * (u * u * ((s + 1) * u + s) + 2)
}

// MARK: - Elastic (Spring)

/// 加速前にバネのように振動するエラスティックイーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 開始時にバネ的な振動を持つイージング値。
public func easeInElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * (2 * Float.pi / 3))
}

/// オーバーシュートして振動してから収束するエラスティックイーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 終了時にバネ的な振動を持つイージング値。
public func easeOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * Float.pi / 3)) + 1
}

/// 両端でバネ振動を持つエラスティックイーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 対称的なバネ振動を持つイージング値。
public func easeInOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    let c = (2 * Float.pi) / 4.5
    if t < 0.5 {
        return -0.5 * pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c)
    }
    return 0.5 * pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c) + 1
}

// MARK: - Bounce

/// ボールが弾んで止まるようなバウンスイーズアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 徐々に小さくなる複数のバウンスを持つイージング値。
public func easeOutBounce(_ t: Float) -> Float {
    if t < 1.0 / 2.75 {
        return 7.5625 * t * t
    } else if t < 2.0 / 2.75 {
        let u = t - 1.5 / 2.75
        return 7.5625 * u * u + 0.75
    } else if t < 2.5 / 2.75 {
        let u = t - 2.25 / 2.75
        return 7.5625 * u * u + 0.9375
    } else {
        let u = t - 2.625 / 2.75
        return 7.5625 * u * u + 0.984375
    }
}

/// ボールが落下してバウンドするようなバウンスイーズインカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 開始時にバウンスを持つイージング値。
public func easeInBounce(_ t: Float) -> Float {
    1 - easeOutBounce(1 - t)
}

/// 遷移の両側でバウンスするバウンスイーズインアウトカーブを適用します。
/// - Parameter t: 0 から 1 の範囲の正規化された時間値。
/// - Returns: 両端で対称的なバウンスを持つイージング値。
public func easeInOutBounce(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * easeInBounce(t * 2)
    }
    return 0.5 * easeOutBounce(t * 2 - 1) + 0.5
}
