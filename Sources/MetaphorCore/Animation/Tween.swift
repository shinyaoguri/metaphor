import simd

// MARK: - Interpolatable Protocol

/// 2つの値の間で線形補間をサポートする型を定義します。
public protocol Interpolatable {
    /// パラメータ t（0.0〜1.0）で2つの値を線形補間します。
    ///
    /// - Parameters:
    ///   - from: 開始値。
    ///   - to: 終了値。
    ///   - t: 補間係数。概念的に 0.0...1.0 にクランプされます。
    /// - Returns: 補間された値。
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

/// イージング関数を使用して値を時間経過で自動的にアニメーションします。
///
/// ```swift
/// let size = tween(from: 0.0, to: 200.0, duration: 1.5, easing: easeOutElastic)
/// size.start()
///
/// // draw() 内で毎フレーム自動更新
/// circle(width/2, height/2, size.value)
/// ```
@MainActor
public final class Tween<T: Interpolatable> {

    // MARK: - Public Properties

    /// 現在の補間値
    public private(set) var value: T

    /// アニメーションが完了したかどうか
    public var isComplete: Bool { state == .complete }

    /// アニメーションが現在実行中かどうか
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

    /// 新しいトゥイーンアニメーションを作成します。
    ///
    /// - Parameters:
    ///   - from: 開始値。
    ///   - to: 終了値。
    ///   - duration: アニメーション時間（秒）。
    ///   - easing: 適用するイージング関数（デフォルト: easeInOutCubic）。
    public init(from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic) {
        self.fromValue = from
        self.toValue = to
        self.duration = max(0.001, duration)
        self.easing = easing
        self.value = from
    }

    // MARK: - Builder Methods

    /// アニメーション開始前のディレイを設定します。
    ///
    /// - Parameter seconds: ディレイ時間（秒）。
    /// - Returns: メソッドチェーン用のこのトゥイーンインスタンス。
    @discardableResult
    public func delay(_ seconds: Float) -> Self {
        self.delayDuration = seconds
        return self
    }

    /// アニメーション完了時に呼び出すコールバックを設定します。
    ///
    /// - Parameter handler: 完了時に呼ばれるクロージャ。
    /// - Returns: メソッドチェーン用のこのトゥイーンインスタンス。
    @discardableResult
    public func onComplete(_ handler: @escaping () -> Void) -> Self {
        self.completionHandler = handler
        return self
    }

    /// アニメーションのリピート回数を設定します（0は無限）。
    ///
    /// - Parameter n: リピート回数。
    /// - Returns: メソッドチェーン用のこのトゥイーンインスタンス。
    @discardableResult
    public func repeatCount(_ n: Int) -> Self {
        self.repeatTotal = max(0, n)
        return self
    }

    /// ヨーヨーモードを有効にします。各サイクルでアニメーション方向が反転します。
    ///
    /// - Returns: メソッドチェーン用のこのトゥイーンインスタンス。
    @discardableResult
    public func yoyo() -> Self {
        self.isYoyo = true
        return self
    }

    // MARK: - Control

    /// アニメーションを最初から開始します。
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

    /// アニメーションを初期値のアイドル状態にリセットします。
    public func reset() {
        state = .idle
        elapsed = 0
        repeatCount = 0
        forward = true
        value = fromValue
    }

    // MARK: - Update (called by TweenManager)

    /// 指定されたデルタタイムでトゥイーン状態を更新します（TweenManager により毎フレーム呼ばれます）。
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
                // 残り時間を即座に適用
                if remaining > 0 {
                    update(remaining)
                }
                return
            }

        case .running:
            elapsed += dt

            if elapsed >= duration {
                // サイクル完了
                repeatCount += 1

                if repeatTotal > 0 && repeatCount >= repeatTotal {
                    // すべてのリピートが終了
                    value = forward ? toValue : fromValue
                    state = .complete
                    completionHandler?()
                    return
                }

                // 次のサイクルを開始
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
