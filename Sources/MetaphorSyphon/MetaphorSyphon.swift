import Metal
import MetaphorCore

/// Syphon 出力モジュール。
///
/// `MetaphorCore` から分離された Syphon 出力実装を提供します。`import metaphor`
/// （アンブレラ）経由ではこのモジュールが自動的にリンクされ、ロード時に出力ファクトリが
/// ``MetaphorOutputRegistry`` へ登録されます。これにより利用者は従来どおり
/// `SketchConfig(syphon: true)` / `syphonName:` / 環境変数 `METAPHOR_SYPHON_NAME` で
/// 手軽に Syphon 出力を有効化できます（`MetaphorSyphon` を明示 import する必要はありません）。
///
/// `MetaphorCore` を単体で import した場合はこのモジュールがリンクされないため、
/// Syphon 依存のない純粋な描画コアとして利用できます。その場合に明示的に Syphon を
/// 有効化したいときは ``enable()`` を呼びます。
public enum MetaphorSyphon {
    /// Syphon 出力ファクトリを明示的に登録します。
    ///
    /// 通常はロード時に C コンストラクタ経由で自動登録されるため呼ぶ必要はありません。
    /// 自動登録が走らない特殊な構成（例: 出力 target を参照しない静的リンク）への
    /// フォールバックとして公開しています。
    public static func enable() {
        installSyphonOutputFactory()
    }
}

/// ``MetaphorOutputRegistry`` に Syphon ファクトリを設定します。
///
/// `factory` は `nonisolated(unsafe)` ストレージのため、ロード時（コンストラクタ）の
/// 非分離コンテキストから格納できます。クロージャ自体は `@MainActor` 型で、実際の生成は
/// 後で `MainActor` 上（`SketchRunner`）から行われます。
private func installSyphonOutputFactory() {
    MetaphorOutputRegistry.factory = { name in SyphonPlugin(name: name) }
}

/// C の `__attribute__((constructor))`（`CMetaphorSyphonBootstrap`）から呼ばれる登録関数。
///
/// アンブレラ `metaphor`（→ `MetaphorSyphon` → `CMetaphorSyphonBootstrap`）がリンクされると、
/// プロセス起動時にこの関数が呼ばれ、利用者コードが `MetaphorSyphon` を明示参照しなくても
/// 出力ファクトリが登録されます。
@_cdecl("metaphor_syphon_register")
public func _metaphorSyphonRegister() {
    installSyphonOutputFactory()
}

// MARK: - 後方互換 facade

extension MetaphorRenderer {
    /// アプリケーション間映像共有用のオプショナルな Syphon 出力。
    ///
    /// 後方互換 facade: Syphon 出力は内部的に ``SyphonPlugin`` として実装されており、
    /// このプロパティは登録済みの ``SyphonPlugin`` が持つ ``SyphonOutput`` を返します。
    public var syphonOutput: SyphonOutput? {
        (plugin(id: SyphonPlugin.id) as? SyphonPlugin)?.output
    }

    /// 指定した名前でアプリケーション間テクスチャ共有用の Syphon サーバーを開始します。
    ///
    /// 内部的には出力フェーズで動作する ``SyphonPlugin`` を登録します。既に Syphon が
    /// 動作中なら差し替えます（二重 publish 防止）。
    /// - Parameter name: Syphon サーバーとして公開する名前
    public func startSyphonServer(name: String) {
        if plugin(id: SyphonPlugin.id) != nil {
            removePlugin(id: SyphonPlugin.id)   // onDetach → 旧サーバー停止
        }
        addPlugin(SyphonPlugin(name: name))     // onAttach(renderer:) → 新サーバー生成
    }

    /// Syphon サーバーを停止し、リソースを解放します。
    public func stopSyphonServer() {
        removePlugin(id: SyphonPlugin.id)       // onDetach → stop + 配列から除去
    }
}
