import CMetaphorSyphonBootstrap
import Metal
import MetaphorCore

/// The Syphon output module.
///
/// Provides the Syphon output implementation, split out from `MetaphorCore`. When
/// imported through the `import metaphor` umbrella, this module is linked automatically,
/// and the output factory is registered with ``MetaphorCore/MetaphorOutputRegistry`` at load time.
/// This lets users continue to easily enable Syphon output via `SketchConfig(syphon: true)`,
/// `syphonName:`, or the `METAPHOR_SYPHON_NAME` environment variable (there is no need to explicitly import `MetaphorSyphon`).
///
/// When `MetaphorCore` is imported on its own, this module is not linked, so it can be
/// used as a pure rendering core with no Syphon dependency. In that case, call
/// ``enable()`` to enable Syphon explicitly.
public enum MetaphorSyphon {
    /// Explicitly registers the Syphon output factory.
    ///
    /// This normally does not need to be called, since registration happens automatically
    /// at load time via a C constructor. It is exposed as a fallback for unusual
    /// configurations where automatic registration does not run (e.g. static linking that never references the output target).
    public static func enable() {
        installSyphonOutputFactory()
    }
}

/// Sets the Syphon factory on ``MetaphorOutputRegistry``.
///
/// `factory` is `nonisolated(unsafe)` storage, so it can be assigned from the
/// non-isolated context at load time (the constructor). The closure itself is
/// `@MainActor`-typed; the actual creation happens later on `MainActor` (`SketchRunner`).
private func installSyphonOutputFactory() {
    // bootstrap.o（ロード時コンストラクタを含む）への実参照。静的アーカイブ経由の
    // リンクでは、シンボル参照のないオブジェクトファイルが selective loading で
    // 落とされ、__attribute__((constructor)) ごと消える。この no-op 呼び出しが
    // MetaphorSyphon → CMetaphorSyphonBootstrap の依存辺を作り、どのリンク構成でも
    // コンストラクタを確実にバイナリへ残す（アンカー）。
    cmetaphor_syphon_bootstrap_touch()
    MetaphorOutputRegistry.factory = { name in SyphonPlugin(name: name) }
}

/// The registration function called from C's `__attribute__((constructor))` (`CMetaphorSyphonBootstrap`).
///
/// When the `metaphor` umbrella (-> `MetaphorSyphon` -> `CMetaphorSyphonBootstrap`) is linked,
/// this function is called at process startup, registering the output factory even if
/// user code never explicitly references `MetaphorSyphon`.
///
/// `internal` で十分（ADR-0007 論点 6）。`@_cdecl` はアクセス修飾子と独立に C リンケージの
/// シンボル `metaphor_syphon_register` を生成するため、`public` にしなくても bootstrap.c から
/// 解決できる。ADR-0001 と同じ 4 組合せ（debug/release × 同一パッケージ/クロスパッケージ）で
/// 自動登録が生きることを再検証済み（#388）。
@_cdecl("metaphor_syphon_register")
func metaphorSyphonRegister() {
    installSyphonOutputFactory()
}

// MARK: - 後方互換 facade

extension MetaphorRenderer {
    /// An optional Syphon output for sharing video between applications.
    ///
    /// Backward-compatibility facade: Syphon output is implemented internally as
    /// `SyphonPlugin`; this property returns the ``SyphonOutput`` held by the registered `SyphonPlugin`.
    public var syphonOutput: SyphonOutput? {
        (plugin(id: SyphonPlugin.id) as? SyphonPlugin)?.output
    }

    /// Starts a Syphon server under the given name for sharing textures between applications.
    ///
    /// Internally, this registers a `SyphonPlugin` that runs in the output phase. If Syphon
    /// is already running, it is replaced (preventing double publishing).
    /// - Parameter name: The name to publish as the Syphon server
    public func startSyphonServer(name: String) {
        if plugin(id: SyphonPlugin.id) != nil {
            removePlugin(id: SyphonPlugin.id)   // onDetach → 旧サーバー停止
        }
        addPlugin(SyphonPlugin(name: name))     // onAttach(renderer:) → 新サーバー生成
    }

    /// Stops the Syphon server and releases its resources.
    public func stopSyphonServer() {
        removePlugin(id: SyphonPlugin.id)       // onDetach → stop + 配列から除去
    }
}
