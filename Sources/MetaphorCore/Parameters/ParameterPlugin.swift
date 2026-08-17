import Foundation
import Metal
import QuartzCore

/// ``ParameterPlugin`` の設定。
///
/// 既定はプロジェクトのカレントディレクトリ配下の `.metaphor/params/`
/// （Probe の `.metaphor/probe/` と同じ流儀。CONTRACT.md 契約点 7）。
///
/// 相対パスは環境変数 `METAPHOR_STATE_DIR`（未設定なら cwd）を基準に解決されます
/// （`.app` 起動では cwd が `/` になるため。Issue #688）。
public struct ParameterStoreConfig: Sendable {
    /// `params.json` を書き出すディレクトリ。
    public var directory: String

    /// 外部（AI エージェント / ツール）が書き込む set-request ファイルのパス。
    public var setRequestFilePath: String

    /// 連続した変更をまとめて書き出すためのデバウンス秒数。
    /// GUI のドラッグ中に毎フレーム書かないためのもので、set-request 起因の
    /// 変更は即時書き出しされます（外部が反映をポーリングで待つため）。
    public var writeDebounce: Double

    public init(
        directory: String = ".metaphor/params",
        setRequestFilePath: String = ".metaphor/params/set-request.json",
        writeDebounce: Double = 0.2
    ) {
        self.directory = MetaphorPaths.resolve(directory)
        self.setRequestFilePath = MetaphorPaths.resolve(setRequestFilePath)
        self.writeDebounce = writeDebounce
    }
}

/// `@Param` で宣言されたパラメータをファイル契約（`.metaphor/params/`）へ橋渡しする
/// プラグイン。
///
/// - **永続化**: 値が変わると `params.json` を原子的に書き出す（デバウンス付き）。
///   起動時にはこのファイルを読み、コード既定値の上に適用する。
/// - **外部書込**: `pre()` で `set-request.json` の mtime を確認し、変化していれば
///   読んで適用 → `appliedRequestId` / `revision` をエコーした `params.json` を即時書出。
///
/// 有効化は自動です（`@Param` が 1 つでも宣言されていれば `SketchRunner` が登録）。
/// オプトアウトは環境変数 `METAPHOR_PARAMS=0`。明示登録も可能:
/// `SketchConfig(plugins: [PluginFactory { ParameterPlugin() }])`。
///
/// ## 性能契約（Probe と同型）
///
/// 変更が無いフレームのコストは **set-request ファイルの `stat()` 1 回**だけです
/// （µs オーダー）。値の書き出しはデバウンス後に 1 回で、エンコードのみメイン
/// スレッド、ディスク I/O は専用の直列キューで行います。
@MainActor
public final class ParameterPlugin: MetaphorPlugin {
    public static let id = "org.metaphor.params"

    public let pluginID: String

    /// プラグイン設定。
    public let config: ParameterStoreConfig

    /// 接続中のスケッチのストア。`onAttach(sketch:)` で解決します。
    ///
    /// 強参照で保持します（ストアはプラグインを参照しないため循環しない。
    /// `@Param` 側からストアへの参照だけが弱参照）。
    private var store: ParameterStore?

    /// 直前に観察した set-request ファイルの mtime。変更検出に利用します。
    private var lastRequestMTime: Date?

    /// 既に処理済みのリクエスト id。重複適用を防ぎます。
    private var lastHandledRequestId: String?

    /// 最後に書き出した revision。これと現在値が違えば書き出し待ち。
    private var lastWrittenRevision: Int?

    /// 書き出し待ちが始まった時刻（デバウンスの起点）。
    private var pendingWriteSince: Double?

    public init(config: ParameterStoreConfig = ParameterStoreConfig()) {
        self.pluginID = ParameterPlugin.id
        self.config = config
    }

    /// `@Param` が宣言されていて、かつオプトアウトされていないか。
    ///
    /// Mirror 走査は起動時 1 回だけです（フレームループには一切現れない）。
    static func shouldAutoRegister(sketch: any Sketch, env: [String: String]) -> Bool {
        guard env["METAPHOR_PARAMS"] != "0" else { return false }
        var mirror: Mirror? = Mirror(reflecting: sketch)
        while let current = mirror {
            if current.children.contains(where: { $0.value is AnyParam }) { return true }
            mirror = current.superclassMirror
        }
        return false
    }

    // MARK: - Lifecycle

    public func onAttach(sketch: any Sketch) {
        guard let store = sketch._context?.params else {
            metaphorDiagnostic("params: SketchContext が未初期化のため Parameter Store を無効化します")
            return
        }
        attach(store: store, sketch: sketch)
    }

    /// 発見 → 永続値ロード → 初回書き出しの本体（`onAttach(sketch:)` の中身）。
    ///
    /// ストアを直接受け取るのは、GPU / ウィンドウ無しでもこの経路を試験できるように
    /// するため（`SketchContext` の構築は Metal デバイスを要求する）。
    func attach(store: ParameterStore, sketch: Any) {
        self.store = store

        // 1. 宣言の発見（プロパティ名 → パラメータ名）。
        store.discover(in: sketch)
        guard !store.isEmpty else { return }

        // 2. 永続値のロード（コード既定値の上に適用）。setup() / draw() は復元値を見る。
        loadPersisted(into: store)

        // 3. 宣言（レンジ・選択肢を含む）を外部へ公開。プロセスが変われば宣言も
        //    変わり得るので revision を 1 つ進めてから書く。
        store.bumpRevisionForStartup()
        flush(store)
    }

    public func onAttach(renderer: MetaphorRenderer) {}

    public func onDetach() {
        // 終了時に取りこぼし（デバウンス待ち）があれば書き出す。
        if let store, lastWrittenRevision != store.revision {
            flush(store)
        }
        store = nil
    }

    public func onStart() {}
    public func onStop() {}
    public func mouseEvent(x: Float, y: Float, button: MouseButton?, type: MouseEventType) {}
    public func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {}
    public func onResize(width: Int, height: Int) {}

    // MARK: - Frame hooks

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        tick(now: CACurrentMediaTime())
    }

    /// フレーム頭の処理本体（set-request のポーリング + 書き出し）。
    ///
    /// 時刻を引数に取るのは、デバウンスの経過をテストから決定的に進めるためです。
    func tick(now: Double) {
        guard let store, !store.isEmpty else { return }
        if pollSetRequestFile(into: store) {
            // 外部は appliedRequestId のエコーで反映を検知するため、デバウンスしない。
            flush(store)
            return
        }
        flushIfDebounceElapsed(store, now: now)
    }

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {}

    // MARK: - ファイル入出力

    private var stateFilePath: String {
        (config.directory as NSString).appendingPathComponent("params.json")
    }

    /// 永続化された `params.json` を読み、名前 + 型が一致する値を適用します。
    private func loadPersisted(into store: ParameterStore) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)) else {
            return  // 初回起動（ファイル無し）は既定値のまま。
        }
        guard let file = ParameterFile.decode(from: data) else {
            metaphorDiagnostic("params: params.json を読めませんでした（既定値で起動します）")
            return
        }
        store.applyPersisted(file)
    }

    /// set-request ファイルの mtime を確認し、変化していれば読んで適用します。
    ///
    /// 読み取り失敗（部分書き込み等）では mtime を確定せず次フレームで再試行します
    /// （Probe の `pollRequestFile()` と同型）。
    ///
    /// - Returns: リクエストを消費したら `true`。
    private func pollSetRequestFile(into store: ParameterStore) -> Bool {
        let path = config.setRequestFilePath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return false
        }
        if let last = lastRequestMTime, last == mtime { return false }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            metaphorDiagnostic("params: set-request.json を読めませんでした（次フレームで再試行）")
            return false
        }
        guard let request = ParameterSetRequest.decode(from: data) else {
            // 壊れた JSON は再読しても直らないので mtime を確定して無視する。
            // consumer は .tmp→rename でアトミックに書く規約（CONTRACT.md 契約点 7）。
            lastRequestMTime = mtime
            metaphorDiagnostic("params: set-request.json をデコードできませんでした（無視）")
            return false
        }

        lastRequestMTime = mtime
        if request.id == lastHandledRequestId { return false }
        lastHandledRequestId = request.id
        store.apply(request)
        return true
    }

    /// デバウンス時間が経過していれば書き出します（GUI ドラッグ・コード代入向け）。
    private func flushIfDebounceElapsed(_ store: ParameterStore, now: Double) {
        guard lastWrittenRevision != store.revision else {
            pendingWriteSince = nil
            return
        }
        guard let since = pendingWriteSince else {
            pendingWriteSince = now
            return
        }
        if now - since >= config.writeDebounce {
            flush(store)
        }
    }

    /// 現在のストア内容を `params.json` へ書き出します。
    private func flush(_ store: ParameterStore) {
        ParameterFileWriter.write(store.fileSnapshot(), directory: config.directory)
        lastWrittenRevision = store.revision
        pendingWriteSince = nil
    }
}
