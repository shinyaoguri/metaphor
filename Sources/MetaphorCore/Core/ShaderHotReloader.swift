import CryptoKit
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

        /// 読んだソースを登録前に整える（2D / 3D は前文を足す）。
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

    // MARK: - 世代の観測（#671）

    /// 監視対象パス（絶対パス） → **いま実際にライブラリに載っている**ソースのハッシュ。
    ///
    /// 「読んだファイルの現在の中身」ではなく「差し替えに成功した中身」を持つのが要点です。
    /// コンパイルに失敗したリロードは旧シェーダを残すので、ここも据え置きになります。
    private var loadedDigests: [String: String] = [:]

    /// 起動からの**着地回数**。差し替えが 1 つでも成功したリロードごとに +1 します。
    ///
    /// 内容ハッシュ（``contentDigest``）と役割が補完的です。内容を編集前に戻すと
    /// ハッシュは元の値に戻りますが、こちらは単調増加なので「反映されたか」を取りこぼしません。
    private(set) var generation = 0

    /// 直近のリロードで出たコンパイルエラー。全て成功したリロードで nil に戻ります。
    ///
    /// これが無いと consumer は「ハッシュが変わらない」＝未反映としか分からず、
    /// 壊れた MSL を保存したときにタイムアウトまで待つことになります（#671）。
    private(set) var lastError: String?

    /// いま載っているファイル由来シェーダ全体の集約ハッシュ（SHA-256 先頭 16 桁）。
    /// ファイル由来のシェーダが 1 つも無ければ nil。
    var contentDigest: String? {
        guard !loadedDigests.isEmpty else { return nil }
        var hasher = SHA256()
        for path in loadedDigests.keys.sorted() {
            hasher.update(data: Data("\(path)\n\(loadedDigests[path]!)\n".utf8))
        }
        return Self.shortHex(hasher.finalize())
    }

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
                prepareSource: Shader3DSource.complete,
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
                prepareSource: PostEffectSource.complete,
                apply: { [weak postEffect] _ in postEffect != nil },
                label: fragment
            )
        )
    }

    private func add(path: String, registration: Registration) {
        let target = (path as NSString).standardizingPath
        registrations[target, default: []].append(registration)
        // 呼び出し元（loadShader / createMaterialFromFile / createPostEffectFromFile）は
        // 既にこのファイルを読んでコンパイルまで済ませているが、どれも読んだソースを
        // ここへ渡さない。public API のシグネチャを変えるより、登録時 1 回だけ読み直す。
        // 直後に書き換わっても watcher が追いかけて直すので実害は無い。
        if loadedDigests[target] == nil,
           let source = try? String(contentsOfFile: target, encoding: .utf8) {
            loadedDigests[target] = Self.digest(of: source)
        }
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
        loadedDigests.removeAll()
    }

    // MARK: - リロード

    /// 指定パスのシェーダを読み直します。監視イベント抜きでも呼べます（テスト・手動リロード）。
    /// - Parameter paths: 読み直すファイルパス。
    /// - Returns: 1 つでも差し替えに成功したかどうか。
    @discardableResult
    func reload(paths: [String]) -> Bool {
        guard let context else { return false }
        var reloaded = false
        // このバッチで出たエラー。最後に `lastError` を丸ごと置き換える（全成功なら nil に戻る）。
        var errors: [String] = []

        for path in paths.map({ ($0 as NSString).standardizingPath }) {
            guard let entries = registrations[path], !entries.isEmpty else { continue }

            let source: String
            do {
                source = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                errors.append(report("\(path) を読めませんでした: \(error.localizedDescription)"))
                continue
            }

            var alive: [Registration] = []
            var landed = true
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
                    errors.append(report("\(entry.label) (\(path)):\n\(error)"))
                    alive.append(entry)
                    landed = false
                }
            }
            registrations[path] = alive
            // 1 つでも失敗したパスは旧シェーダが残っている＝未反映。刻印も据え置く（#671）。
            // 生存登録が空（対象オブジェクトが解放済み）になったパスは台帳から落とす。
            if alive.isEmpty {
                loadedDigests[path] = nil
            } else if landed {
                loadedDigests[path] = Self.digest(of: source)
            }
        }

        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if reloaded {
            generation += 1
            applySideEffects()
        }
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
    ///
    /// - Returns: `lastError`（= `frame.json` の `shaders.lastError`）に積む短縮版。
    ///   MSL コンパイラの出力は長くなりうるので wire 用に切り詰めます。
    @discardableResult
    private func report(_ message: String) -> String {
        FileHandle.standardError.write(
            "[metaphor] shader hot reload failed: \(message)\n".data(using: .utf8)!)
        return Self.truncate(message, to: 500)
    }

    // MARK: - ハッシュ

    /// 1 ファイル分のソースのハッシュ（SHA-256 先頭 16 桁）。
    private static func digest(of source: String) -> String {
        shortHex(SHA256.hash(data: Data(source.utf8)))
    }

    /// ダイジェストを 16 進小文字の先頭 16 桁へ。64 bit あれば編集の取り違えは起きず、
    /// AI が読む wire を短く保てます（暗号用途ではない）。
    private static func shortHex(_ digest: some Sequence<UInt8>) -> String {
        String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// 長すぎるメッセージを末尾省略で切ります。
    private static func truncate(_ message: String, to limit: Int) -> String {
        message.count <= limit ? message : String(message.prefix(limit)) + "…"
    }
}
