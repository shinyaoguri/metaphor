import Foundation

// MARK: - Easing Function Type

/// イージング関数の型エイリアス（t: 0..1 → 0..1）
public typealias EasingFunction = (Float) -> Float

/// イージング関数を使って2つの値を補間
public func ease(_ t: Float, from a: Float, to b: Float, using f: EasingFunction) -> Float {
    a + (b - a) * f(t)
}

// MARK: - Quad (二次)

public func easeInQuad(_ t: Float) -> Float {
    t * t
}

public func easeOutQuad(_ t: Float) -> Float {
    t * (2 - t)
}

public func easeInOutQuad(_ t: Float) -> Float {
    if t < 0.5 {
        return 2 * t * t
    }
    return -1 + (4 - 2 * t) * t
}

// MARK: - Cubic (三次)

public func easeInCubic(_ t: Float) -> Float {
    t * t * t
}

public func easeOutCubic(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u + 1
}

public func easeInOutCubic(_ t: Float) -> Float {
    if t < 0.5 {
        return 4 * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u + 1
}

// MARK: - Quart (四次)

public func easeInQuart(_ t: Float) -> Float {
    t * t * t * t
}

public func easeOutQuart(_ t: Float) -> Float {
    let u = t - 1
    return 1 - u * u * u * u
}

public func easeInOutQuart(_ t: Float) -> Float {
    if t < 0.5 {
        return 8 * t * t * t * t
    }
    let u = t - 1
    return 1 - 8 * u * u * u * u
}

// MARK: - Quint (五次)

public func easeInQuint(_ t: Float) -> Float {
    t * t * t * t * t
}

public func easeOutQuint(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u * u * u + 1
}

public func easeInOutQuint(_ t: Float) -> Float {
    if t < 0.5 {
        return 16 * t * t * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u * u * u + 1
}

// MARK: - Sine (サイン)

public func easeInSine(_ t: Float) -> Float {
    1 - cos(t * Float.pi / 2)
}

public func easeOutSine(_ t: Float) -> Float {
    sin(t * Float.pi / 2)
}

public func easeInOutSine(_ t: Float) -> Float {
    0.5 * (1 - cos(Float.pi * t))
}

// MARK: - Expo (指数)

public func easeInExpo(_ t: Float) -> Float {
    t == 0 ? 0 : pow(2, 10 * (t - 1))
}

public func easeOutExpo(_ t: Float) -> Float {
    t == 1 ? 1 : 1 - pow(2, -10 * t)
}

public func easeInOutExpo(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    if t < 0.5 {
        return 0.5 * pow(2, 20 * t - 10)
    }
    return 1 - 0.5 * pow(2, -20 * t + 10)
}

// MARK: - Circ (円弧)

public func easeInCirc(_ t: Float) -> Float {
    1 - sqrt(1 - t * t)
}

public func easeOutCirc(_ t: Float) -> Float {
    let u = t - 1
    return sqrt(1 - u * u)
}

public func easeInOutCirc(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * (1 - sqrt(1 - 4 * t * t))
    }
    let u = 2 * t - 2
    return 0.5 * (sqrt(1 - u * u) + 1)
}

// MARK: - Back (オーバーシュート)

private let backS: Float = 1.70158

public func easeInBack(_ t: Float) -> Float {
    t * t * ((backS + 1) * t - backS)
}

public func easeOutBack(_ t: Float) -> Float {
    let u = t - 1
    return u * u * ((backS + 1) * u + backS) + 1
}

public func easeInOutBack(_ t: Float) -> Float {
    let s = backS * 1.525
    if t < 0.5 {
        let u = 2 * t
        return 0.5 * (u * u * ((s + 1) * u - s))
    }
    let u = 2 * t - 2
    return 0.5 * (u * u * ((s + 1) * u + s) + 2)
}

// MARK: - Elastic (バネ)

public func easeInElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * (2 * Float.pi / 3))
}

public func easeOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * Float.pi / 3)) + 1
}

public func easeInOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    let c = (2 * Float.pi) / 4.5
    if t < 0.5 {
        return -0.5 * pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c)
    }
    return 0.5 * pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c) + 1
}

// MARK: - Bounce (バウンス)

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

public func easeInBounce(_ t: Float) -> Float {
    1 - easeOutBounce(1 - t)
}

public func easeInOutBounce(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * easeInBounce(t * 2)
    }
    return 0.5 * easeOutBounce(t * 2 - 1) + 0.5
}
