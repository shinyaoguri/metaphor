import QuartzCore

/// アニメーションおよびレンダリングループのフレームタイミングを管理します。
public final class FrameTimer {
    private var startTime: Double
    private var lastFrameTime: Double
    private var frameCount: UInt64 = 0

    /// タイマー作成時からの経過時間を秒単位で返します。
    public var elapsed: Double {
        CACurrentMediaTime() - startTime
    }

    /// 前フレームからの経過時間（デルタタイム）を返します。
    public private(set) var deltaTime: Double = 0

    /// 現在のフレームレートをFPSで返します。
    public private(set) var fps: Double = 0

    /// 処理された総フレーム数を返します。
    public var totalFrames: UInt64 {
        frameCount
    }

    public init() {
        let now = CACurrentMediaTime()
        startTime = now
        lastFrameTime = now
    }

    /// 各フレームの先頭でタイマーを更新します。
    public func update() {
        let now = CACurrentMediaTime()
        deltaTime = now - lastFrameTime
        fps = deltaTime > 0 ? 1.0 / deltaTime : 0
        lastFrameTime = now
        frameCount += 1
    }

    /// タイマーを初期状態にリセットします。
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

/// 0 から 1 の範囲で振動するサイン波を生成します。
/// - Parameters:
///   - time: 現在の時間値。
///   - frequency: Hz 単位の振動周波数。
/// - Returns: サインカーブに従う 0 から 1 の値。
public func sine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((sin(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// 0 から 1 の範囲で振動するコサイン波を生成します。
/// - Parameters:
///   - time: 現在の時間値。
///   - frequency: Hz 単位の振動周波数。
/// - Returns: コサインカーブに従う 0 から 1 の値。
public func cosine01(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((cos(time * frequency * 2 * .pi) + 1) * 0.5)
}

/// 0 から 1 の範囲で振動する三角波を生成します。
/// - Parameters:
///   - time: 現在の時間値。
///   - frequency: Hz 単位の振動周波数。
/// - Returns: 三角波に従う 0 から 1 の値。
public func triangle(_ time: Double, frequency: Double = 1.0) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return Float(t < 0.5 ? t * 2 : 2 - t * 2)
}

/// 0 から 1 の範囲で振動するノコギリ波を生成します。
/// - Parameters:
///   - time: 現在の時間値。
///   - frequency: Hz 単位の振動周波数。
/// - Returns: 線形に上昇してリセットする 0 から 1 の値。
public func sawtooth(_ time: Double, frequency: Double = 1.0) -> Float {
    Float((time * frequency).truncatingRemainder(dividingBy: 1.0))
}

/// 0 または 1 を出力する矩形波を生成します。
/// - Parameters:
///   - time: 現在の時間値。
///   - frequency: Hz 単位の振動周波数。
///   - duty: 0 から 1 の範囲のデューティ比。
/// - Returns: 現在の位相に応じて 1.0 または 0.0。
public func square(_ time: Double, frequency: Double = 1.0, duty: Double = 0.5) -> Float {
    let t = (time * frequency).truncatingRemainder(dividingBy: 1.0)
    return t < duty ? 1.0 : 0.0
}
