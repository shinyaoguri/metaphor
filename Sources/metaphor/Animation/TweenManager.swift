/// Manage and automatically update a collection of tweens each frame.
///
/// SketchContext calls `update()` in `beginFrame()` every frame,
/// automatically advancing all registered tweens. Completed tweens are removed automatically.
@MainActor
public final class TweenManager {

    /// Type-erased wrapper for a tween of any interpolatable type.
    private struct AnyTween {
        let update: (Float) -> Void
        let isComplete: () -> Bool
    }

    private var tweens: [AnyTween] = []

    public init() {}

    /// Register a tween for automatic updates.
    ///
    /// - Parameter tween: The tween to add to the manager.
    public func add<T: Interpolatable>(_ tween: Tween<T>) {
        tweens.append(AnyTween(
            update: { dt in tween.update(dt) },
            isComplete: { tween.isComplete }
        ))
    }

    /// Update all registered tweens by the given delta time (call once per frame).
    ///
    /// - Parameter deltaTime: The elapsed time since the last frame, in seconds.
    public func update(_ deltaTime: Float) {
        for t in tweens {
            t.update(deltaTime)
        }
        tweens.removeAll { $0.isComplete() }
    }

    /// Remove all registered tweens.
    public func clear() {
        tweens.removeAll()
    }

    /// Return the number of currently registered tweens.
    public var count: Int { tweens.count }
}
