import Metal

/// 出力プラグイン（Syphon / NDI 等）のファクトリ登録ポイント。
///
/// `MetaphorCore` は具体的な出力実装（Syphon など）を**参照しません**。出力を提供する
/// 別 target（例: `MetaphorSyphon`）が自身のロード時にここへファクトリを登録し、
/// ``SketchRunner`` の自動配線（`config.syphon` / `config.syphonName` /
/// `METAPHOR_SYPHON_NAME` / ヘッドレス起動）がそれを**透過的に**利用します。
///
/// これにより `MetaphorCore` 単体は Syphon 等のバイナリ依存を持たない純粋な描画コアになり、
/// かつ `import metaphor`（アンブレラ）利用者には従来どおりの手軽な Syphon 出力を提供できます。
///
/// ## 登録の仕組み
/// `MetaphorSyphon` は C の `__attribute__((constructor))` から `@_cdecl` 関数を呼び、
/// プロセス起動時に ``factory`` を設定します。アンブレラ（`metaphor`）を介して
/// `MetaphorSyphon` がリンクされる限り（＝現行の全利用経路）、利用者コードが
/// `MetaphorSyphon` を明示参照しなくても登録が行われます。
public enum MetaphorOutputRegistry {
    /// 名前から出力プラグインを生成するファクトリ。
    ///
    /// 出力 target のロード時（C コンストラクタ経由）に**格納のみ**が行われ、
    /// 実際の呼び出しは ``makeOutput(name:)`` を通じて `MainActor` 上で行われます。
    /// 格納はロード時の単一スレッドで一度だけ行われるため `nonisolated(unsafe)` とします。
    public nonisolated(unsafe) static var factory: (@MainActor (String) -> MetaphorOutputPlugin)?

    /// 登録済みファクトリで出力プラグインを生成します。未登録なら `nil`。
    /// - Parameter name: 解決済みの出力サーバー名。
    @MainActor
    public static func makeOutput(name: String) -> MetaphorOutputPlugin? {
        factory?(name)
    }
}
