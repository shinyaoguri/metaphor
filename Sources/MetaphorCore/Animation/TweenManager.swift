/// トゥイーンのコレクションを管理し、毎フレーム自動更新します。
///
/// SketchContext が `beginFrame()` 内で毎フレーム `update()` を呼び出し、
/// 登録されたすべてのトゥイーンを自動的に進行させます。完了したトゥイーンは自動的に削除されます。
@MainActor
public final class TweenManager {

    /// 任意の Interpolatable 型のトゥイーン用の型消去ラッパー
    private struct AnyTween {
        let update: (Float) -> Void
        let isComplete: () -> Bool
    }

    private var tweens: [AnyTween] = []

    public init() {}

    /// トゥイーンを自動更新対象として登録します。
    ///
    /// - Parameter tween: マネージャに追加するトゥイーン。
    public func add<T: Interpolatable>(_ tween: Tween<T>) {
        tweens.append(AnyTween(
            update: { dt in tween.update(dt) },
            isComplete: { tween.isComplete }
        ))
    }

    /// 指定されたデルタタイムで登録済みの全トゥイーンを更新します（毎フレーム1回呼び出し）。
    ///
    /// - Parameter deltaTime: 前フレームからの経過時間（秒）。
    public func update(_ deltaTime: Float) {
        for t in tweens {
            t.update(deltaTime)
        }
        tweens.removeAll { $0.isComplete() }
    }

    /// 登録済みのすべてのトゥイーンを削除します。
    public func clear() {
        tweens.removeAll()
    }

    /// 現在登録されているトゥイーンの数
    public var count: Int { tweens.count }
}
