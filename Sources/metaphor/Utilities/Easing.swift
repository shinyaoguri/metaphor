import Foundation

// MARK: - Easing Function Type

/// Define a type alias for easing functions that map t in 0..1 to an output in 0..1.
public typealias EasingFunction = (Float) -> Float

/// Interpolate between two values using an easing function.
/// - Parameters:
///   - t: The normalized time value in the range 0 to 1.
///   - a: The start value.
///   - b: The end value.
///   - f: The easing function to shape the interpolation.
/// - Returns: The interpolated value between a and b.
public func ease(_ t: Float, from a: Float, to b: Float, using f: EasingFunction) -> Float {
    a + (b - a) * f(t)
}

// MARK: - Quad (Quadratic)

/// Apply a quadratic ease-in curve that starts slow and accelerates.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value, equal to t squared.
public func easeInQuad(_ t: Float) -> Float {
    t * t
}

/// Apply a quadratic ease-out curve that starts fast and decelerates.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using an inverted quadratic.
public func easeOutQuad(_ t: Float) -> Float {
    t * (2 - t)
}

/// Apply a quadratic ease-in-out curve that accelerates then decelerates.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using a piecewise quadratic.
public func easeInOutQuad(_ t: Float) -> Float {
    if t < 0.5 {
        return 2 * t * t
    }
    return -1 + (4 - 2 * t) * t
}

// MARK: - Cubic

/// Apply a cubic ease-in curve that starts slow and accelerates sharply.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value, equal to t cubed.
public func easeInCubic(_ t: Float) -> Float {
    t * t * t
}

/// Apply a cubic ease-out curve that starts fast and decelerates sharply.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using an inverted cubic.
public func easeOutCubic(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u + 1
}

/// Apply a cubic ease-in-out curve that accelerates then decelerates smoothly.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using a piecewise cubic.
public func easeInOutCubic(_ t: Float) -> Float {
    if t < 0.5 {
        return 4 * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u + 1
}

// MARK: - Quart (Quartic)

/// Apply a quartic ease-in curve that starts very slow and accelerates steeply.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value, equal to t to the fourth power.
public func easeInQuart(_ t: Float) -> Float {
    t * t * t * t
}

/// Apply a quartic ease-out curve that starts fast and decelerates steeply.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using an inverted quartic.
public func easeOutQuart(_ t: Float) -> Float {
    let u = t - 1
    return 1 - u * u * u * u
}

/// Apply a quartic ease-in-out curve that accelerates then decelerates with a steep slope.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using a piecewise quartic.
public func easeInOutQuart(_ t: Float) -> Float {
    if t < 0.5 {
        return 8 * t * t * t * t
    }
    let u = t - 1
    return 1 - 8 * u * u * u * u
}

// MARK: - Quint (Quintic)

/// Apply a quintic ease-in curve that starts extremely slow and accelerates aggressively.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value, equal to t to the fifth power.
public func easeInQuint(_ t: Float) -> Float {
    t * t * t * t * t
}

/// Apply a quintic ease-out curve that starts fast and decelerates aggressively.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using an inverted quintic.
public func easeOutQuint(_ t: Float) -> Float {
    let u = t - 1
    return u * u * u * u * u + 1
}

/// Apply a quintic ease-in-out curve that accelerates then decelerates with an aggressive slope.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using a piecewise quintic.
public func easeInOutQuint(_ t: Float) -> Float {
    if t < 0.5 {
        return 16 * t * t * t * t * t
    }
    let u = 2 * t - 2
    return 0.5 * u * u * u * u * u + 1
}

// MARK: - Sine

/// Apply a sinusoidal ease-in curve that starts slow using a cosine function.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on one quarter of a cosine wave.
public func easeInSine(_ t: Float) -> Float {
    1 - cos(t * Float.pi / 2)
}

/// Apply a sinusoidal ease-out curve that decelerates using a sine function.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on one quarter of a sine wave.
public func easeOutSine(_ t: Float) -> Float {
    sin(t * Float.pi / 2)
}

/// Apply a sinusoidal ease-in-out curve that accelerates and decelerates smoothly.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on half a cosine wave.
public func easeInOutSine(_ t: Float) -> Float {
    0.5 * (1 - cos(Float.pi * t))
}

// MARK: - Expo (Exponential)

/// Apply an exponential ease-in curve that starts near zero and accelerates exponentially.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using base-2 exponential growth.
public func easeInExpo(_ t: Float) -> Float {
    t == 0 ? 0 : pow(2, 10 * (t - 1))
}

/// Apply an exponential ease-out curve that decelerates exponentially toward 1.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using base-2 exponential decay.
public func easeOutExpo(_ t: Float) -> Float {
    t == 1 ? 1 : 1 - pow(2, -10 * t)
}

/// Apply an exponential ease-in-out curve with exponential acceleration and deceleration.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value using piecewise base-2 exponential functions.
public func easeInOutExpo(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    if t < 0.5 {
        return 0.5 * pow(2, 20 * t - 10)
    }
    return 1 - 0.5 * pow(2, -20 * t + 10)
}

// MARK: - Circ (Circular)

/// Apply a circular ease-in curve that accelerates along a quarter-circle arc.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on a circular curve.
public func easeInCirc(_ t: Float) -> Float {
    1 - sqrt(1 - t * t)
}

/// Apply a circular ease-out curve that decelerates along a quarter-circle arc.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on an inverted circular curve.
public func easeOutCirc(_ t: Float) -> Float {
    let u = t - 1
    return sqrt(1 - u * u)
}

/// Apply a circular ease-in-out curve that follows a half-circle arc.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value based on piecewise circular curves.
public func easeInOutCirc(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * (1 - sqrt(1 - 4 * t * t))
    }
    let u = 2 * t - 2
    return 0.5 * (sqrt(1 - u * u) + 1)
}

// MARK: - Back (Overshoot)

private let backS: Float = 1.70158

/// Apply a back ease-in curve that pulls back before accelerating forward.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value that briefly goes below 0 before reaching 1.
public func easeInBack(_ t: Float) -> Float {
    t * t * ((backS + 1) * t - backS)
}

/// Apply a back ease-out curve that overshoots 1 before settling back.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value that briefly exceeds 1 before settling.
public func easeOutBack(_ t: Float) -> Float {
    let u = t - 1
    return u * u * ((backS + 1) * u + backS) + 1
}

/// Apply a back ease-in-out curve that pulls back, accelerates, overshoots, and settles.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with overshoot on both ends.
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

/// Apply an elastic ease-in curve that oscillates like a spring before accelerating.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with spring-like oscillation at the start.
public func easeInElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * (2 * Float.pi / 3))
}

/// Apply an elastic ease-out curve that overshoots and oscillates before settling.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with spring-like oscillation at the end.
public func easeOutElastic(_ t: Float) -> Float {
    if t == 0 { return 0 }
    if t == 1 { return 1 }
    return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * Float.pi / 3)) + 1
}

/// Apply an elastic ease-in-out curve with spring oscillation on both ends.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with symmetric spring-like oscillation.
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

/// Apply a bounce ease-out curve that simulates a ball bouncing to rest.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with multiple diminishing bounces.
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

/// Apply a bounce ease-in curve that simulates a ball dropping with bounces.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with bounces at the beginning.
public func easeInBounce(_ t: Float) -> Float {
    1 - easeOutBounce(1 - t)
}

/// Apply a bounce ease-in-out curve that bounces on both sides of the transition.
/// - Parameter t: The normalized time value in the range 0 to 1.
/// - Returns: The eased value with symmetric bounces at both ends.
public func easeInOutBounce(_ t: Float) -> Float {
    if t < 0.5 {
        return 0.5 * easeInBounce(t * 2)
    }
    return 0.5 * easeOutBounce(t * 2 - 1) + 0.5
}
