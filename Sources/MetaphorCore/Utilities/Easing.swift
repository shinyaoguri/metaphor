import Foundation

// MARK: - Easing Function Type

/// A type alias for an easing function that maps t from 0..1 to 0..1.
public typealias EasingFunction = (Float) -> Float

/// Interpolates between two values using an easing function.
/// - Parameters:
///   - t: The normalized time value, in the range 0 to 1.
///   - a: The starting value.
///   - b: The ending value.
///   - f: The easing function that shapes the interpolation curve.
/// - Returns: The interpolated value between a and b.
///
/// ### Result
///
/// Two shapes driven by the same `t`. The upper one uses ``easeInOutCubic(_:)``, the lower one
/// has no easing (linear). Only the upper one slows down at both ends and speeds up in the middle.
///
/// <!-- reference-shot -->
///
/// @Row {
///    @Column(size: 1) {
///       ![ease(_:from:to:using:) の実行結果（動き）](https://i.gyazo.com/d3575413e871cb48991e71e3cf0f115f.gif)
///    }
///    @Column(size: 2) {
///       ```swift
///       background(18)
///       noStroke()
///
///       let p = Float(frameCount % 72) / 36
///       let t = p < 1 ? p : 2 - p
///
///       fill(120, 200, 255)
///       circle(
///           ease(t, from: 60, to: 420,
///                using: easeInOutCubic),
///           130, 56
///       )
///
///       fill(130)
///       circle(60 + t * 360, 240, 56)
///       ```
///    }
/// }
public func ease(_ t: Float, from a: Float, to b: Float, using f: EasingFunction) -> Float {
    a + (b - a) * f(t)
}

// MARK: - Quad (Quadratic)

/// Applies a quadratic ease-in curve that starts slowly and accelerates.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, equal to t squared.
public func easeInQuad(_ t: Float) -> Float {
    t * t
}

/// Applies a quadratic ease-out curve that starts fast and decelerates.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from an inverted quadratic function.
public func easeOutQuad(_ t: Float) -> Float {
    t * (2 - t)
}

/// Applies a quadratic ease-in-out curve that accelerates and then decelerates.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from a piecewise quadratic function.
public func easeInOutQuad(_ t: Float) -> Float {
    if t < 0.5 {
        return 2 * t * t
    }
    return -1 + (4 - 2 * t) * t
}

// MARK: - Cubic

/// Applies a cubic ease-in curve that starts slowly and accelerates sharply.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, equal to t cubed.
public func easeInCubic(_ t: Float) -> Float {
    t * t * t
}

/// Applies a cubic ease-out curve that starts fast and decelerates sharply.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from an inverted cubic function.
public func easeOutCubic(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u + 1
}

/// Applies a cubic ease-in-out curve that accelerates and then decelerates smoothly.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from a piecewise cubic function.
public func easeInOutCubic(_ t: Float) -> Float {
    if t < 0.5 {
        return 4 * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u + 1
}

// MARK: - Quart (Quartic)

/// Applies a quartic ease-in curve that starts very slowly and accelerates steeply.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, equal to t raised to the fourth power.
public func easeInQuart(_ t: Float) -> Float {
    t * t * t * t
}

/// Applies a quartic ease-out curve that starts fast and decelerates steeply.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from an inverted quartic function.
public func easeOutQuart(_ t: Float) -> Float {
    let u = t - 1
    return 1 - u * u * u * u
}

/// Applies a quartic ease-in-out curve that accelerates steeply and then decelerates.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from a piecewise quartic function.
public func easeInOutQuart(_ t: Float) -> Float {
    if t < 0.5 {
        return 8 * t * t * t * t
    }
    let u = t - 1
    return 1 - 8 * u * u * u * u
}

// MARK: - Quint (Quintic)

/// Applies a quintic ease-in curve that starts extremely slowly and accelerates intensely.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, equal to t raised to the fifth power.
public func easeInQuint(_ t: Float) -> Float {
    t * t * t * t * t
}

/// Applies a quintic ease-out curve that starts fast and decelerates intensely.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from an inverted quintic function.
public func easeOutQuint(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u * u * u + 1
}

/// Applies a quintic ease-in-out curve that accelerates intensely and then decelerates.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from a piecewise quintic function.
public func easeInOutQuint(_ t: Float) -> Float {
    if t < 0.5 {
        return 16 * t * t * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u * u * u + 1
}

// MARK: - Sine

/// Applies a sinusoidal ease-in curve that starts slowly, using the cosine function.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on a quarter of a cosine wave.
public func easeInSine(_ t: Float) -> Float {
    1 - cos(t * Float.pi / 2)
}

/// Applies a sinusoidal ease-out curve that decelerates, using the sine function.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on a quarter of a sine wave.
public func easeOutSine(_ t: Float) -> Float {
    sin(t * Float.pi / 2)
}

/// Applies a sinusoidal ease-in-out curve that accelerates and decelerates smoothly.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on half of a cosine wave.
public func easeInOutSine(_ t: Float) -> Float {
    0.5 * (1 - cos(Float.pi * t))
}

// MARK: - Expo (Exponential)

/// Applies an exponential ease-in curve that accelerates exponentially from near zero.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from base-2 exponential growth.
public func easeInExpo(_ t: Float) -> Float {
    t == 0 ? 0 : pow(2, 10 * (t - 1))
}

/// Applies an exponential ease-out curve that decelerates exponentially toward 1.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from base-2 exponential decay.
public func easeOutExpo(_ t: Float) -> Float {
    t == 1 ? 1 : 1 - pow(2, -10 * t)
}

/// Applies an exponential ease-in-out curve with exponential acceleration and deceleration.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value from a piecewise base-2 exponential function.
public func easeInOutExpo(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    if t < 0.5 {
        return 0.5 * pow(2, 20 * t - 10)
    }
    return 1 - 0.5 * pow(2, -20 * t + 10)
}

// MARK: - Circ (Circular)

/// Applies a circular ease-in curve that accelerates along a quarter-circle arc.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on a circular curve.
public func easeInCirc(_ t: Float) -> Float {
    1 - sqrt(1 - t * t)
}

/// Applies a circular ease-out curve that decelerates along a quarter-circle arc.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on an inverted circular curve.
public func easeOutCirc(_ t: Float) -> Float {
    let u = t - 1
    return sqrt(1 - u * u)
}

/// Applies a circular ease-in-out curve that follows a semicircular arc.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value based on a piecewise circular curve.
public func easeInOutCirc(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * (1 - sqrt(1 - 4 * t * t))
    }
    let u = 2 * t - 2
    return 0.5 * (sqrt(1 - u * u) + 1)
}

// MARK: - Back (Overshoot)

private let backS: Float = 1.70158

/// Applies a back ease-in curve that pulls back before accelerating.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, which briefly dips below 0 before reaching 1.
public func easeInBack(_ t: Float) -> Float {
    t * t * ((backS + 1) * t - backS)
}

/// Applies a back ease-out curve that overshoots past 1 and then settles back.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, which briefly exceeds 1 before settling.
public func easeOutBack(_ t: Float) -> Float {
    let u = t - 1
    return u * u * ((backS + 1) * u + backS) + 1
}

/// Applies a back ease-in-out curve that pulls back, accelerates, overshoots, and settles.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, which overshoots at both ends.
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

/// Applies an elastic ease-in curve that oscillates like a spring before accelerating.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with a spring-like oscillation at the start.
public func easeInElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * (2 * Float.pi / 3))
}

/// Applies an elastic ease-out curve that overshoots, oscillates, and then settles.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with a spring-like oscillation at the end.
public func easeOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * Float.pi / 3)) + 1
}

/// Applies an elastic ease-in-out curve with spring oscillation at both ends.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with symmetric spring oscillation.
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

/// Applies a bounce ease-out curve, like a ball bouncing to a stop.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with several bounces that grow progressively smaller.
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

/// Applies a bounce ease-in curve, like a ball falling and bouncing.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with bounces at the start.
public func easeInBounce(_ t: Float) -> Float {
    1 - easeOutBounce(1 - t)
}

/// Applies a bounce ease-in-out curve that bounces on both sides of the transition.
/// - Parameter t: The normalized time value, in the range 0 to 1.
/// - Returns: The eased value, with symmetric bounces at both ends.
public func easeInOutBounce(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * easeInBounce(t * 2)
    }
    return 0.5 * easeOutBounce(t * 2 - 1) + 0.5
}
