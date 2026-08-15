import Foundation
import Metal

/// ``StatePlugin`` の設定。
///
/// 既定はプロジェクトのカレントディレクトリ配下の `.metaphor/state/`
/// （Probe の `.metaphor/probe/`・Parameter Store の `.metaphor/params/` と同じ流儀。
/// CONTRACT.md 契約点 8）。
///
/// 相対パスは環境変数 `METAPHOR_STATE_DIR`（未設定なら cwd）を基準に解決されます
/// （`.app` 起動では cwd が `/` になるため。Issue #688）。
public struct SketchStateConfig: Sendable {
    /// `state.json` を書き出すディレクトリ。
    public var directory: String

    /// 外部（`metaphor watch` / AI ツール）が書き込む save-request ファイルのパス。
    public var saveRequestFilePath: String

    public init(
        directory: String = ".metaphor/state",
        saveRequestFilePath: String = ".metaphor/state/save-request.json"
    ) {
        self.directory = MetaphorPaths.resolve(directory)
        self.saveRequestFilePath = MetaphorPaths.resolve(saveRequestFilePath)
    }
}

/// リロードをまたいでスケッチの状態を運ぶプラグイン（保存側）。
///
/// `metaphor watch` は再ビルド後に子プロセスを作り直すため、`draw()` が積み上げた
/// 状態（パーティクル・シミュレーション）と時計が毎回ゼロに戻ります。本プラグインは
/// **kill される直前のスナップショット**を `.metaphor/state/state.json` へ書き出し、
/// 次のプロセスが環境変数 `METAPHOR_RESTORE_STATE` 経由でそれを読み戻します。
///
/// - **保存**: `pre()` で `save-request.json` の mtime を確認し、変化していれば
///   ``Sketch/saveState()`` を呼んで `state.json` をアトミックに書き出す。
///   応答した `id` をエコーするので、consumer はタイムアウトを待たずに ready を検知できる。
/// - **復元**: 新しいプロセス側の担当（``SketchRunner`` が `setup()` の後に
///   ``Sketch/restoreState(_:)`` を呼ぶ）。
///
/// 有効化は `metaphor watch` のヘッドレス実行（`METAPHOR_VIEWER=1`）で自動。
/// 素の `swift run` でも試したいときは `METAPHOR_STATE=1`、オプトアウトは
/// `METAPHOR_STATE=0`。明示登録も可能:
/// `SketchConfig(plugins: [PluginFactory { StatePlugin() }])`。
///
/// ## 性能契約（Probe / Parameter Store と同型）
///
/// リクエストが無いフレームのコストは **save-request ファイルの `stat()` 1 回**だけです
/// （µs オーダー）。``Sketch/saveState()`` の呼び出しとディスク書き込みはリクエスト時のみで、
/// これはリロード直前の 1 回に限られます。
@MainActor
public final class StatePlugin: MetaphorPlugin {
    public static let id = "org.metaphor.state"

    public let pluginID: String

    /// プラグイン設定。
    public let config: SketchStateConfig

    /// 接続中のスケッチ（`saveState()` の呼び出し先）。
    private weak var sketch: (any Sketch)?

    /// 接続中のコンテキスト（`frameCount` の読み取り元）。
    private weak var context: SketchContext?

    /// 直前に観察した save-request ファイルの mtime。変更検出に利用します。
    private var lastRequestMTime: Date?

    /// 既に処理済みのリクエスト id。重複保存を防ぎます。
    private var lastHandledRequestId: String?

    public init(config: SketchStateConfig = SketchStateConfig()) {
        self.pluginID = StatePlugin.id
        self.config = config
    }

    /// 自動登録すべきか。
    ///
    /// 既定で有効なのはヘッドレス（`metaphor watch` の子プロセス）だけです
    /// — save-request を書く相手が居ない素の `swift run` で毎フレーム `stat()` を
    /// 払う理由が無いため。`METAPHOR_STATE=1` で明示的に有効、`=0` で無効。
    static func shouldAutoRegister(env: [String: String]) -> Bool {
        switch env["METAPHOR_STATE"] {
        case "0": return false
        case "1": return true
        default: return env["METAPHOR_VIEWER"] == "1"
        }
    }

    // MARK: - Lifecycle

    public func onAttach(sketch: any Sketch) {
        self.sketch = sketch
        self.context = sketch._context
    }

    public func onAttach(renderer: MetaphorRenderer) {}
    public func onDetach() {
        sketch = nil
        context = nil
    }
    public func onStart() {}
    public func onStop() {}
    public func mouseEvent(x: Float, y: Float, button: MouseButton?, type: MouseEventType) {}
    public func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {}
    public func onResize(width: Int, height: Int) {}

    // MARK: - Frame hooks

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        tick(elapsedSeconds: time)
    }

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}

    /// フレーム頭の処理本体（save-request のポーリング → 保存）。
    ///
    /// 経過秒数を引数に取るのは、テストから決定的な時計を渡せるようにするためです。
    func tick(elapsedSeconds: Double) {
        guard let request = pollSaveRequestFile() else { return }
        save(
            requestId: request.id,
            frameCount: context?.frameCount ?? 0,
            elapsedSeconds: elapsedSeconds
        )
    }

    // MARK: - 保存

    /// 現在の状態を `state.json` へ書き出します。
    ///
    /// ``Sketch/saveState()`` が `nil` を返しても（= 状態を持たないスケッチ）
    /// **ファイルは書きます** — consumer は `savedRequestId` のエコーで ready を
    /// 判定するため、無応答にすると毎回タイムアウト待ちになるからです。
    /// このとき `runtime` 節だけが載り、`preserveClock` の復元は機能します。
    @discardableResult
    func save(requestId: String?, frameCount: Int, elapsedSeconds: Double) -> Bool {
        let payload = sketch?.saveState()
        let file = SketchStateFile(
            savedRequestId: requestId,
            frameCount: frameCount,
            elapsedSeconds: elapsedSeconds,
            payload: payload
        )
        return SketchStateWriter.write(file, directory: config.directory)
    }

    /// save-request ファイルの mtime を確認し、変化していれば読んで返します。
    ///
    /// 読み取り失敗（部分書き込み等）では mtime を確定せず次フレームで再試行します
    /// （Probe の `pollRequestFile()` / Parameter Store と同型）。
    private func pollSaveRequestFile() -> SketchStateSaveRequest? {
        let path = config.saveRequestFilePath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        if let last = lastRequestMTime, last == mtime { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            metaphorDiagnostic("state: save-request.json を読めませんでした（次フレームで再試行）")
            return nil
        }
        guard let request = SketchStateSaveRequest.decode(from: data) else {
            // 壊れた JSON は再読しても直らないので mtime を確定して無視する。
            // consumer は .tmp→rename でアトミックに書く規約（CONTRACT.md 契約点 8）。
            lastRequestMTime = mtime
            metaphorDiagnostic("state: save-request.json をデコードできませんでした（無視）")
            return nil
        }

        lastRequestMTime = mtime
        if request.id == lastHandledRequestId { return nil }
        lastHandledRequestId = request.id
        return request
    }
}

// MARK: - 復元（新しいプロセス側）

/// 環境変数 `METAPHOR_RESTORE_STATE` が指す `state.json` を読み戻す入口。
///
/// **失敗はすべて黙って初期状態へフォールバック**します（`METAPHOR_DEBUG=1` のときだけ
/// stderr に理由を出す）。開発ツールの都合でスケッチが起動しない・落ちるのは本末転倒だからです。
enum SketchStateRestore {
    /// 復元対象を読み取ります。環境変数が無い/読めない/壊れている場合は `nil`。
    static func load(env: [String: String]) -> RestoredSketchState? {
        guard let raw = env["METAPHOR_RESTORE_STATE"], !raw.isEmpty else { return nil }
        // 契約上は絶対パスだが、相対で渡ってきても `METAPHOR_STATE_DIR`（未設定なら cwd）
        // 基準で解決する。絶対パスはそのまま（Issue #688）。
        let path = MetaphorPaths.resolve(raw)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            metaphorDiagnostic("state: METAPHOR_RESTORE_STATE のファイルを読めませんでした（初期状態で起動します）")
            return nil
        }
        guard let restored = RestoredSketchState.decode(from: data) else {
            metaphorDiagnostic("state: state.json をデコードできませんでした（初期状態で起動します）")
            return nil
        }
        return restored
    }
}
