import Metal

/// 出力プラグイン（Syphon / NDI 等）の**旧**ファクトリ登録ポイント。
///
/// ``MetaphorOutputProviders`` に置き換わりました。単一の ``factory`` しか持てないため、複数の
/// 出力モジュールが自動登録すると後勝ちで上書きされる問題があり（#792）、provider を `id` 付きで
/// 複数登録できる ``MetaphorOutputProviders/register(_:)`` を使ってください。
///
/// 互換のため ``factory`` に登録されたファクトリは引き続き起動時の自動配線に使われます
/// （``MetaphorOutputProviders`` の走査結果の末尾に、従来どおりの名前解決で 1 件加わる）。
/// この型は deprecation 期間の後に削除されます。
public enum MetaphorOutputRegistry {
    /// ``factory`` の実体。deprecated な公開プロパティを経由せずに Core 内部から読むための置き場
    /// （CI は `-warnings-as-errors` なので、Core 自身が deprecated API を参照できない）。
    ///
    /// 出力 target のロード時（C コンストラクタ経由）に格納だけが行われ、実際の呼び出しは
    /// `makeLegacyOutput(context:)` を通じて `MainActor` 上で行われる。格納はロード時の
    /// 単一スレッドで一度だけ行われるため `nonisolated(unsafe)`。
    nonisolated(unsafe) static var legacyFactory: (@MainActor (String) -> MetaphorOutputPlugin)?

    /// 名前から出力プラグインを生成するファクトリ。
    @available(*, deprecated, message: "Register a MetaphorOutputProvider with MetaphorOutputProviders.register(_:) instead")
    public static var factory: (@MainActor (String) -> MetaphorOutputPlugin)? {
        get { legacyFactory }
        set { legacyFactory = newValue }
    }

    /// 登録済みファクトリで出力プラグインを生成します。未登録なら `nil`。
    /// - Parameter name: 解決済みの出力サーバー名。
    @available(*, deprecated, message: "Use MetaphorOutputProviders; outputs are resolved from a MetaphorOutputContext")
    @MainActor
    public static func makeOutput(name: String) -> MetaphorOutputPlugin? {
        legacyFactory?(name)
    }

    /// 旧 ``factory`` を provider 走査に混ぜるための橋渡し。
    ///
    /// 名前解決は旧 `SketchRunner.resolveSyphonName` / `SketchWindow` と同じ:
    /// プライマリは `METAPHOR_SYPHON_NAME`（空文字は未設定扱い）> ``SketchConfig/syphonName`` >
    /// （``SketchConfig/syphon`` が `true` なら ``SketchConfig/title``）、
    /// セカンダリウィンドウは ``SketchWindowConfig/syphonName`` のみ。名前が決まらなければ `nil`
    /// （ヘッドレスでも暗黙には立てない。ADR-0014）。
    /// 旧ファクトリの出力は Syphon 相当として ``PluginRequirements/externalRenderLoop`` を宣言する。
    @MainActor
    static func makeLegacyOutput(context: MetaphorOutputContext) -> MetaphorOutputProviders.ResolvedOutput? {
        guard let factory = legacyFactory,
              let name = legacyOutputName(context: context) else {
            return nil
        }
        return MetaphorOutputProviders.ResolvedOutput(
            providerID: "org.metaphor.legacy-output-factory",
            plugin: factory(name),
            requirements: [.externalRenderLoop]
        )
    }

    /// 旧 API の名前解決（純粋関数。テスト用に分離）。
    nonisolated static func legacyOutputName(context: MetaphorOutputContext) -> String? {
        switch context.scope {
        case .primary(let config):
            if let name = context.environment["METAPHOR_SYPHON_NAME"], !name.isEmpty { return name }
            if let name = config.syphonName { return name }
            if config.syphon { return config.title }
            return nil
        case .window(let config):
            return config.syphonName
        }
    }
}
