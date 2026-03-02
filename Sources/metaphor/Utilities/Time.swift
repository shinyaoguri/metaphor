import QuartzCore

/// フレームタイミングを管理するクラス
public final class FrameTimer {
    private var startTime: Double
    private var lastFrameTime: Double
    private var frameCount: UInt64 = 0

    /// 経過時間（秒）
    public var elapsed: Double {
        CACurrentMediaTime() - startTime
    }

    /// 前フレームからの経過時間（デルタタイム）
    public private(set) var deltaTime: Double = 0

    /// フレームレート（FPS）
    public private(set) var fps: Double = 0

    /// 総フレーム数
    public var totalFrames: UInt64 {
        frameCount
    }

    public init() {
        let now = CACurrentMediaTime()
        startTime = now
        lastFrameTime = now
    }

    /// フレームを更新
    /// 毎フレームの最初に呼び出す
    public func update() {
        let now = CACurrentMediaTime()
        deltaTime = now - lastFrameTime
        fps = deltaTime > 0 ? 1.0 / deltaTime : 0
        lastFrameTime = now
        frameCount += 1
    }

    /// タイマーをリセット
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

/// サイン波（0から1の範囲）
public func sine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((sin(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// コサイン波（0から1の範囲）
public func cosine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((cos(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// 三角波（0から1の範囲）
public func triangle(_ time: Double, frequency: Double = 1.0) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return Float(t < 0.5 ? t * 2 : 2 - t * 2)
}

/// ノコギリ波（0から1の範囲）
public func sawtooth(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((time * frequency).truncatingRemainder(dividingBy: 1.0))
}

/// 矩形波（0か1）
public func square(_ time: Double, frequency: Double = 1.0, duty: Double = 0.5) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return t < duty ? 1.0 : 0.0
}
