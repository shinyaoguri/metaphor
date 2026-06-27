import Metal

/// 登録された ``SketchSubsystem`` 群のライフサイクルと毎フレーム更新を自動で駆動する
/// プラグイン。
///
/// `config.plugins` に追加してオプトインで使います。`draw()` 内で各サブシステムの
/// `update()` / `step(dt)` を手動で呼ぶ代わりに、本マネージャがフレーム前フック
/// （``MetaphorPlugin/pre(commandBuffer:time:)``）で `update(deltaTime:)` をまとめて呼びます。
///
/// ```swift
/// var config: SketchConfig {
///     SketchConfig(plugins: [
///         PluginFactory { [audio, physics] in AutoSubsystemManager([audio, physics]) }
///     ])
/// }
/// ```
///
/// 登録しなければ従来どおり手動更新のままで、既存スケッチには一切影響しません。
@MainActor
public final class AutoSubsystemManager: MetaphorPlugin {
    public let pluginID: String
    private let subsystems: [any SketchSubsystem]
    /// 前フレームの時刻（秒）。deltaTime 算出に使う。初回は nil。
    private var lastTime: Double?

    /// - Parameters:
    ///   - subsystems: 自動駆動するサブシステム群（登録順に更新されます）。
    ///   - pluginID: プラグイン識別子（既定で十分。複数併用時のみ変更）。
    public init(
        _ subsystems: [any SketchSubsystem],
        pluginID: String = "org.metaphor.auto-subsystems"
    ) {
        self.subsystems = subsystems
        self.pluginID = pluginID
    }

    public func onStart() {
        lastTime = nil
        for subsystem in subsystems { subsystem.onStart() }
    }

    public func onStop() {
        for subsystem in subsystems { subsystem.onStop() }
    }

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        let deltaTime: Float = lastTime.map { Float(time - $0) } ?? 0
        lastTime = time
        for subsystem in subsystems { subsystem.update(deltaTime: deltaTime) }
    }
}
