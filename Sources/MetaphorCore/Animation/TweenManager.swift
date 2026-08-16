/// トゥイーンのコレクションを管理し、毎フレーム自動更新します。
///
/// SketchContext が `beginFrame()` 内で毎フレーム `update()` を呼び出し、
/// 登録されたすべてのトゥイーンを自動的に進行させます。
///
/// 登録の寿命は `Tween` の状態機械に一致します。動いているもの（`.delaying` / `.running`）
/// だけを保持し、完了したものと、まだ始まっていない / `reset()` されたものは
/// 次の `update(_:)` で外れます。外れたトゥイーンも `start()` すれば自動的に戻るので、
/// 手で登録し直す必要はありません。
@MainActor
public final class TweenManager {

    /// 任意の Interpolatable 型のトゥイーン用の型消去ラッパー
    ///
    /// `update` / `isDormant` はどちらもトゥイーンを**強参照**でキャプチャします
    /// （マネージャが登録中のトゥイーンを保持する、という所有関係そのもの）。
    /// そのぶん、登録から外す条件が実態とずれるとメモリ滞留に直結します。
    private struct AnyTween {
        let id: ObjectIdentifier
        let update: (Float) -> Void
        let isDormant: () -> Bool
    }

    private var tweens: [AnyTween] = []

    /// 登録済みトゥイーンの同一性。`tweens` を線形に探さずに重複を弾くための索引で、
    /// 常に `tweens` と同じ集合を指します。
    private var registered: Set<ObjectIdentifier> = []

    public init() {}

    /// トゥイーンを自動更新対象として登録します。
    ///
    /// すでに登録済みのインスタンスは無視します（同じトゥイーンが 2 回登録されると
    /// 1 フレームに 2 回 `update` が走り、そのトゥイーンだけ倍速になるため）。
    ///
    /// - Parameter tween: マネージャに追加するトゥイーン。
    public func add<T: Interpolatable>(_ tween: Tween<T>) {
        let id = ObjectIdentifier(tween)
        guard registered.insert(id).inserted else { return }

        // 外れたあとに start() されたら戻れるよう、登録先を覚えさせる（弱参照）。
        tween.registrar = self

        tweens.append(AnyTween(
            id: id,
            update: { dt in tween.update(dt) },
            isDormant: { tween.isDormant }
        ))
    }

    /// 指定されたデルタタイムで登録済みの全トゥイーンを更新します（毎フレーム1回呼び出し）。
    ///
    /// 更新後、動いていないトゥイーン（完了済み・未開始・`reset()` 済み）を登録から外します。
    ///
    /// - Parameter deltaTime: 前フレームからの経過時間（秒）。
    public func update(_ deltaTime: Float) {
        for t in tweens {
            t.update(deltaTime)
        }
        tweens.removeAll { entry in
            let dormant = entry.isDormant()
            if dormant { registered.remove(entry.id) }
            return dormant
        }
    }

    /// 登録済みのすべてのトゥイーンを削除します。
    public func clear() {
        tweens.removeAll()
        registered.removeAll()
    }

    /// 現在登録されているトゥイーンの数
    public var count: Int { tweens.count }
}
