import QuartzCore

/// Manages frame timing for animation and the draw loop.
public final class FrameTimer {
    private var startTime: Double
    private var lastFrameTime: Double
    private var frameCount: UInt64 = 0

    /// The time in seconds elapsed since the timer was created.
    public var elapsed: Double {
        CACurrentMediaTime() - startTime
    }

    /// The time elapsed since the previous frame (the delta time).
    public private(set) var deltaTime: Double = 0

    /// The current frame rate in frames per second.
    public private(set) var fps: Double = 0

    /// The total number of frames processed.
    public var totalFrames: UInt64 {
        frameCount
    }

    public init() {
        let now = CACurrentMediaTime()
        startTime = now
        lastFrameTime = now
    }

    /// Updates the timer at the start of each frame.
    public func update() {
        let now = CACurrentMediaTime()
        deltaTime = now - lastFrameTime
        fps = deltaTime > 0 ? 1.0 / deltaTime : 0
        lastFrameTime = now
        frameCount += 1
    }

    /// Resets the timer to its initial state.
    public func reset() {
        let now = CACurrentMediaTime()
        startTime = now
        lastFrameTime = now
        frameCount = 0
        deltaTime = 0
        fps = 0
    }
}

// MARK: - Time-based Animation Helpers

/// Generates a sine wave that oscillates between 0 and 1.
/// - Parameters:
///   - time: The current time value.
///   - frequency: The oscillation frequency in hertz.
/// - Returns: A value between 0 and 1 that follows a sine curve.
public func sine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((sin(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// Generates a cosine wave that oscillates between 0 and 1.
/// - Parameters:
///   - time: The current time value.
///   - frequency: The oscillation frequency in hertz.
/// - Returns: A value between 0 and 1 that follows a cosine curve.
public func cosine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((cos(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// Generates a triangle wave that oscillates between 0 and 1.
/// - Parameters:
///   - time: The current time value.
///   - frequency: The oscillation frequency in hertz.
/// - Returns: A value between 0 and 1 that follows a triangle wave.
public func triangle(_ time: Double, frequency: Double = 1.0) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return Float(t < 0.5 ? t * 2 : 2 - t * 2)
}

/// Generates a sawtooth wave that oscillates between 0 and 1.
/// - Parameters:
///   - time: The current time value.
///   - frequency: The oscillation frequency in hertz.
/// - Returns: A value between 0 and 1 that rises linearly and then resets.
public func sawtooth(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((time * frequency).truncatingRemainder(dividingBy: 1.0))
}

/// Generates a square wave that outputs either 0 or 1.
/// - Parameters:
///   - time: The current time value.
///   - frequency: The oscillation frequency in hertz.
///   - duty: The duty cycle, in the range 0 to 1.
/// - Returns: Either 1.0 or 0.0, depending on the current phase.
public func square(_ time: Double, frequency: Double = 1.0, duty: Double = 0.5) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return t < duty ? 1.0 : 0.0
}
