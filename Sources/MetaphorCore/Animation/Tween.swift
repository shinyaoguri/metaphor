import simd

// MARK: - Interpolatable Protocol

/// Define a type that supports linear interpolation between two values.
public protocol Interpolatable {
    /// Linearly interpolate between two values by parameter t (0.0 to 1.0).
    ///
    /// - Parameters:
    ///   - from: The start value.
    ///   - to: The end value.
    ///   - t: The interpolation factor, clamped conceptually to 0.0...1.0.
    /// - Returns: The interpolated value.
    static func interpolate(from: Self, to: Self, t: Float) -> Self
}

// MARK: - Interpolatable Conformances

extension Float: Interpolatable {
    public static func interpolate(from: Float, to: Float, t: Float) -> Float {
        from + (to - from) * t
    }
}

extension SIMD2<Float>: Interpolatable {
    public static func interpolate(from: SIMD2<Float>, to: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        from + (to - from) * t
    }
}

extension SIMD3<Float>: Interpolatable {
    public static func interpolate(from: SIMD3<Float>, to: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        from + (to - from) * t
    }
}

extension SIMD4<Float>: Interpolatable {
    public static func interpolate(from: SIMD4<Float>, to: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        from + (to - from) * t
    }
}

extension Color: Interpolatable {
    public static func interpolate(from: Color, to: Color, t: Float) -> Color {
        Color(
            r: Float.interpolate(from: from.r, to: to.r, t: t),
            g: Float.interpolate(from: from.g, to: to.g, t: t),
            b: Float.interpolate(from: from.b, to: to.b, t: t),
            a: Float.interpolate(from: from.a, to: to.a, t: t)
        )
    }
}

// MARK: - Tween

/// Animate a value automatically over time using an easing function.
///
/// ```swift
/// let size = tween(from: 0.0, to: 200.0, duration: 1.5, easing: easeOutElastic)
/// size.start()
///
/// // Automatically updated each frame inside draw()
/// circle(width/2, height/2, size.value)
/// ```
@MainActor
public final class Tween<T: Interpolatable> {

    // MARK: - Public Properties

    /// The current interpolated value.
    public private(set) var value: T

    /// Indicate whether the animation has completed.
    public var isComplete: Bool { state == .complete }

    /// Indicate whether the animation is currently running.
    public var isActive: Bool { state == .running }

    // MARK: - Configuration

    private let fromValue: T
    private let toValue: T
    private let duration: Float
    private let easing: EasingFunction

    private var delayDuration: Float = 0
    private var repeatTotal: Int = 1
    private var isYoyo: Bool = false
    private var completionHandler: (() -> Void)?

    // MARK: - State

    enum State {
        case idle
        case delaying
        case running
        case complete
    }

    private var state: State = .idle
    private var elapsed: Float = 0
    private var repeatCount: Int = 0
    private var forward: Bool = true

    // MARK: - Initialization

    /// Create a new tween animation.
    ///
    /// - Parameters:
    ///   - from: The start value.
    ///   - to: The end value.
    ///   - duration: The animation duration in seconds.
    ///   - easing: The easing function to apply (defaults to easeInOutCubic).
    public init(from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic) {
        self.fromValue = from
        self.toValue = to
        self.duration = max(0.001, duration)
        self.easing = easing
        self.value = from
    }

    // MARK: - Builder Methods

    /// Set the delay before the animation starts.
    ///
    /// - Parameter seconds: The delay duration in seconds.
    /// - Returns: This tween instance for method chaining.
    @discardableResult
    public func delay(_ seconds: Float) -> Self {
        self.delayDuration = seconds
        return self
    }

    /// Set a callback to invoke when the animation completes.
    ///
    /// - Parameter handler: The closure to call on completion.
    /// - Returns: This tween instance for method chaining.
    @discardableResult
    public func onComplete(_ handler: @escaping () -> Void) -> Self {
        self.completionHandler = handler
        return self
    }

    /// Set the number of times the animation repeats (0 means infinite).
    ///
    /// - Parameter n: The repeat count.
    /// - Returns: This tween instance for method chaining.
    @discardableResult
    public func repeatCount(_ n: Int) -> Self {
        self.repeatTotal = max(0, n)
        return self
    }

    /// Enable yoyo mode, which reverses the animation direction on each cycle.
    ///
    /// - Returns: This tween instance for method chaining.
    @discardableResult
    public func yoyo() -> Self {
        self.isYoyo = true
        return self
    }

    // MARK: - Control

    /// Start the animation from the beginning.
    public func start() {
        elapsed = 0
        repeatCount = 0
        forward = true
        value = fromValue

        if delayDuration > 0 {
            state = .delaying
        } else {
            state = .running
        }
    }

    /// Reset the animation to its idle state with the initial value.
    public func reset() {
        state = .idle
        elapsed = 0
        repeatCount = 0
        forward = true
        value = fromValue
    }

    // MARK: - Update (called by TweenManager)

    /// Update the tween state by the given delta time (called each frame by TweenManager).
    func update(_ dt: Float) {
        switch state {
        case .idle, .complete:
            return

        case .delaying:
            elapsed += dt
            if elapsed >= delayDuration {
                let remaining = elapsed - delayDuration
                elapsed = 0
                state = .running
                // Apply the remaining time immediately
                if remaining > 0 {
                    update(remaining)
                }
                return
            }

        case .running:
            elapsed += dt

            if elapsed >= duration {
                // Cycle complete
                repeatCount += 1

                if repeatTotal > 0 && repeatCount >= repeatTotal {
                    // All repeats finished
                    value = forward ? toValue : fromValue
                    state = .complete
                    completionHandler?()
                    return
                }

                // Start next cycle
                elapsed -= duration
                if isYoyo {
                    forward.toggle()
                }
            }

            let t = min(elapsed / duration, 1.0)
            let easedT = easing(t)

            if forward {
                value = T.interpolate(from: fromValue, to: toValue, t: easedT)
            } else {
                value = T.interpolate(from: toValue, to: fromValue, t: easedT)
            }
        }
    }
}
