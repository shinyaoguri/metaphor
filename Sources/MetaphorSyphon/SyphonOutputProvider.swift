import MetaphorCore

/// Syphon 出力の自動配線を担う ``MetaphorCore/MetaphorOutputProvider``。
///
/// ロード時（C コンストラクタ → `metaphor_syphon_register`）または ``MetaphorSyphon/enable()`` で
/// ``MetaphorCore/MetaphorOutputProviders`` に登録され、`SketchRunner` / `SketchWindow` の起動ごとに
/// ``makeOutput(context:)`` が呼ばれる。Syphon サーバー名が決まれば `SyphonPlugin` を返し、
/// 決まらなければ `nil`（= このスケッチでは Syphon を publish しない）。
///
/// Syphon は MadMapper 等の受け手がウィンドウの可視状態と無関係にフレームを期待するため、
/// ``MetaphorCore/PluginRequirements/externalRenderLoop`` を宣言する（`.displayLink` のままの
/// スケッチはタイマー駆動へ切り替わる = 従来の「Syphon ありなら timer」）。
///
/// `internal`: 利用者は `SketchConfig(syphon:)` / `syphonName:` / `METAPHOR_SYPHON_NAME` か、
/// 明示的な `MetaphorSyphon.enable()` を使う（ADR-0007 論点 6 と同じ扱い）。
struct SyphonOutputProvider: MetaphorOutputProvider {
    /// 登録 id（テストや `unregister(id:)` から参照する）。
    static let providerID = "org.metaphor.syphon"

    var id: String { Self.providerID }
    let requirements: PluginRequirements = [.externalRenderLoop]

    @MainActor
    func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin? {
        guard let name = Self.resolveOutputName(context: context) else { return nil }
        return SyphonPlugin(name: name)
    }

    /// この起動で publish する Syphon サーバー名（無効なら `nil`）。
    ///
    /// プライマリは `resolveSyphonName(config:env:requiresOutput:)`（ヘッドレスは出力しか無いので
    /// `requiresOutput: true` = `config.syphon` に関わらず `title` へ落ちる）、セカンダリウィンドウは
    /// ``MetaphorCore/SketchWindowConfig/syphonName`` のみ（環境変数・`syphon` フラグは見ない = 従来どおり）。
    nonisolated static func resolveOutputName(context: MetaphorOutputContext) -> String? {
        switch context.scope {
        case .primary(let config):
            return resolveSyphonName(
                config: config, env: context.environment, requiresOutput: context.isHeadless
            )
        case .window(let config):
            return config.syphonName
        }
    }

    /// 出力（Syphon）サーバーの実効名を解決します（ウィンドウ / ヘッドレス共通）。
    ///
    /// 優先順位: 環境変数 `METAPHOR_SYPHON_NAME` > ``MetaphorCore/SketchConfig/syphonName`` >
    /// （``MetaphorCore/SketchConfig/syphon`` が `true` なら ``MetaphorCore/SketchConfig/title``）。
    /// いずれも無ければ `nil`（= 出力無効）。空文字の環境変数は未設定として扱います。
    ///
    /// ヘッドレス（`METAPHOR_VIEWER=1`）は「ウィンドウ無し・出力のみ」で、名前が決まらないと
    /// 何も見えないプロセスになります。この経路は `requiresOutput: true` を渡し、
    /// ``MetaphorCore/SketchConfig/syphon`` が `false` でも `title` へ落ちる（= 戻り値は
    /// 必ず非 `nil`）ようにします。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定。
    ///   - env: 参照する環境変数（テストから注入可能）。
    ///   - requiresOutput: 出力が必須の経路（= ヘッドレス）なら `true`。
    /// - Returns: 出力サーバー名。無効なら `nil`（`requiresOutput: true` では `nil` にならない）。
    nonisolated static func resolveSyphonName(
        config: SketchConfig, env: [String: String], requiresOutput: Bool = false
    ) -> String? {
        if let name = env["METAPHOR_SYPHON_NAME"], !name.isEmpty { return name }
        if let name = config.syphonName { return name }
        if config.syphon || requiresOutput { return config.title }
        return nil
    }
}
