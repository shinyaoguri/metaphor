import simd

// MARK: - Interpolatable Protocol

/// 補間可能な型のプロトコル
public protocol Interpolatable {
    /// 2つの値を t (0.0〜1.0) で線形補間
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

/// イージング関数を使った値の自動アニメーション
///
/// ```swift
/// let size = tween(from: 0.0, to: 200.0, duration: 1.5, easing: easeOutElastic)
/// size.start()
///
/// // draw() 内で自動更新
/// circle(width/2, height/2, size.value)
/// ```
@MainActor
public final class Tween<T: Interpolatable> {

    // MARK: - Public Properties

    /// 現在の補間値
    public private(set) var value: T

    /// アニメーション完了フラグ
    public var isComplete: Bool { state == .complete }

    /// アニメーション中かどうか
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

    /// Tween を作成
    /// - Parameters:
    ///   - from: 開始値
    ///   - to: 終了値
    ///   - duration: 所要時間（秒）
    ///   - easing: イージング関数（デフォルト: easeInOutCubic）
    public init(from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic) {
        self.fromValue = from
        self.toValue = to
        self.duration = max(0.001, duration)
        self.easing = easing
        self.value = from
    }

    // MARK: - Builder Methods

    /// 開始前のディレイを設定
    @discardableResult
    public func delay(_ seconds: Float) -> Self {
        self.delayDuration = seconds
        return self
    }

    /// 完了時のコールバック
    @discardableResult
    public func onComplete(_ handler: @escaping () -> Void) -> Self {
        self.completionHandler = handler
        return self
    }

    /// リピート回数（0=無限）
    @discardableResult
    public func repeatCount(_ n: Int) -> Self {
        self.repeatTotal = max(0, n)
        return self
    }

    /// 往復モード
    @discardableResult
    public func yoyo() -> Self {
        self.isYoyo = true
        return self
    }

    // MARK: - Control

    /// アニメーションを開始
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

    /// アニメーションをリセット
    public func reset() {
        state = .idle
        elapsed = 0
        repeatCount = 0
        forward = true
        value = fromValue
    }

    // MARK: - Update (TweenManager が呼ぶ)

    /// 内部更新（TweenManager から毎フレーム呼ばれる）
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
                // 余った時間を即座に反映
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
                    // 全リピート完了
                    value = forward ? toValue : fromValue
                    state = .complete
                    completionHandler?()
                    return
                }

                // 次のサイクル
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
