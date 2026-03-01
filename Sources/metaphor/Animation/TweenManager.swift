/// Tween の一括管理・自動更新マネージャー
///
/// SketchContext の beginFrame() で毎フレーム update() が呼ばれ、
/// 登録された全 Tween を自動進行させる。完了した Tween は自動除去される。
@MainActor
public final class TweenManager {

    /// 型消去された Tween ラッパー
    private struct AnyTween {
        let update: (Float) -> Void
        let isComplete: () -> Bool
    }

    private var tweens: [AnyTween] = []

    public init() {}

    /// Tween を登録
    public func add<T: Interpolatable>(_ tween: Tween<T>) {
        tweens.append(AnyTween(
            update: { dt in tween.update(dt) },
            isComplete: { tween.isComplete }
        ))
    }

    /// 全 Tween を更新（毎フレーム呼ぶ）
    public func update(_ deltaTime: Float) {
        for t in tweens {
            t.update(deltaTime)
        }
        tweens.removeAll { $0.isComplete() }
    }

    /// 全 Tween をクリア
    public func clear() {
        tweens.removeAll()
    }

    /// 登録中の Tween 数
    public var count: Int { tweens.count }
}
