import Foundation

/// ファイルから読んだシェーダを、保存のたびに自動で再コンパイルして差し替えます
/// （#648 / Epic #291 E3）。
///
/// `loadShader()`（2D）/ `createMaterialFromFile()`（3D）/ `createPostEffectFromFile()`（postFX）
/// が**自動で登録**するので、スケッチ側に書くコードはありません。監視の仕組みは
/// ``ShaderFileWatcher`` 1 つで、3 経路が同じ台帳に載ります。
///
/// ## 失敗しても落ちない
///
/// 書きかけの MSL は必ずコンパイルに失敗します。失敗したリロードは**直前の動くシェーダを
/// そのまま残し**（``ShaderLibrary/reload(key:source:)`` が成功時にだけ差し替える）、
/// エラーを stderr に出すだけです。直して保存すればそのまま復帰します。
@MainActor
final class ShaderHotReloader {
    /// 1 ファイルに紐づくリロード手順。
    private struct Registration {
        /// ``ShaderLibrary`` の登録キー。
        let libraryKey: String

        /// 読んだソースを登録前に整える（2D だけ前文を足す）。
        let prepareSource: (String) -> String

        /// ライブラリ差し替え後に、対象オブジェクトの関数を引き直す。
        /// 対象が解放済みなら `false` を返し、この登録は台帳から落とします。
        let apply: (ShaderLibrary) throws -> Bool

        /// ログに出す名前（フラグメント関数名）。
        let label: String
    }

    /// 監視対象パス（絶対パス） → リロード手順。
    private var registrations: [String: [Registration]] = [:]

    /// 実際に監視を始めたときだけ生成します（ファイル由来のシェーダが無ければスレッドも無し）。
    private var watcher: ShaderFileWatcher?

    /// キャッシュ破棄と再描画のために参照するコンテキスト。
    private weak var context: SketchContext?

    init(context: SketchContext) {
        self.context = context
    }

    // MARK: - 登録

    /// 2D カスタムシェーダ（``Shader2D``）を監視対象に加えます。
    func register(shader: Shader2D, path: String, fragment: String) {
        add(
            path: path,
            registration: Registration(
                libraryKey: shader.libraryKey,
                prepareSource: Shader2DSource.complete,
                apply: { [weak shader] library in
                    guard let shader else { return false }
                    try shader.reload(shaderLibrary: library)
                    return true
                },
                label: fragment
            )
        )
    }

    /// 3D カスタムマテリアル（``CustomMaterial``）を監視対象に加えます。
    func register(material: CustomMaterial, path: String, fragment: String) {
        add(
            path: path,
            registration: Registration(
                libraryKey: material.libraryKey,
                prepareSource: { $0 },
                apply: { [weak material] library in
                    guard let material else { return false }
                    try material.reload(shaderLibrary: library)
                    return true
                },
                label: fragment
            )
        )
    }

    /// ポストエフェクト（``CustomPostEffect``）を監視対象に加えます。
    ///
    /// `CustomPostEffect` は関数を自前で持たず、``PostProcessPipeline`` がパイプライン構築時に
    /// ライブラリから引き直します。したがって差し替え後にすることは無く、
    /// `invalidatePipelines()`（``applySideEffects()`` が行う）だけで新しい関数が載ります。
    func register(postEffect: CustomPostEffect, path: String, fragment: String) {
        add(
            path: path,
            registration: Registration(
                libraryKey: postEffect.libraryKey,
                prepareSource: { $0 },
                apply: { [weak postEffect] _ in postEffect != nil },
                label: fragment
            )
        )
    }

    private func add(path: String, registration: Registration) {
        let target = (path as NSString).standardizingPath
        registrations[target, default: []].append(registration)
        startWatchingIfNeeded()
        watcher?.watch(path: target)
        metaphorDiagnostic(
            "shader hot reload: watching \(target) for \(registration.label)")
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil else { return }
        watcher = ShaderFileWatcher { [weak self] paths in
            _ = self?.reload(paths: paths)
        }
    }

    /// 監視を止めます（スケッチ終了時）。
    func stop() {
        watcher?.stop()
        watcher = nil
        registrations.removeAll()
    }

    // MARK: - リロード

    /// 指定パスのシェーダを読み直します。監視イベント抜きでも呼べます（テスト・手動リロード）。
    /// - Parameter paths: 読み直すファイルパス。
    /// - Returns: 1 つでも差し替えに成功したかどうか。
    @discardableResult
    func reload(paths: [String]) -> Bool {
        guard let context else { return false }
        var reloaded = false

        for path in paths.map({ ($0 as NSString).standardizingPath }) {
            guard let entries = registrations[path], !entries.isEmpty else { continue }

            let source: String
            do {
                source = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                report("\(path) を読めませんでした: \(error.localizedDescription)")
                continue
            }

            var alive: [Registration] = []
            for entry in entries {
                do {
                    try context.renderer.shaderLibrary.reload(
                        key: entry.libraryKey, source: entry.prepareSource(source))
                    if try entry.apply(context.renderer.shaderLibrary) {
                        alive.append(entry)
                        reloaded = true
                        metaphorDiagnostic(
                            "shader hot reload: reloaded \(entry.label) from \(path)")
                    }
                } catch {
                    // コンパイル失敗。直前の動くシェーダは残っているので描画は続く。
                    report("\(entry.label) (\(path)):\n\(error)")
                    alive.append(entry)
                }
            }
            registrations[path] = alive
        }

        if reloaded { applySideEffects() }
        return reloaded
    }

    /// 差し替え後にパイプラインキャッシュを捨て、止まっているスケッチなら 1 枚描き直します。
    private func applySideEffects() {
        guard let context else { return }
        context.canvas3D.clearCustomPipelineCache()
        context.renderer.postProcessPipeline?.invalidatePipelines()
        // `noLoop()` 中はフレームが進まないので、リロードそのものを再描画の合図にする。
        // これが無いと「保存したのに絵が変わらない」になる。
        if !context.isLooping { context.redraw() }
    }

    /// リロードの失敗を伝えます。
    ///
    /// `metaphorWarning` と違って **DEBUG ゲートを通しません**。ホットリロード自体が
    /// 開発時のみ有効な機能で、その価値は「なぜ絵が変わらないか」がすぐ分かることに
    /// あるためです。stdout を汚さないよう stderr に書きます（MCP の JSON-RPC 対策）。
    private func report(_ message: String) {
        FileHandle.standardError.write(
            "[metaphor] shader hot reload failed: \(message)\n".data(using: .utf8)!)
    }
}
