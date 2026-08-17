import AppKit
import Metal

/// このプロトコルに準拠してスケッチを定義します。
///
/// クラスに `@main` を付与し、`draw()` を実装すると、
/// ウィンドウ、レンダラー、Canvas2D が自動的にセットアップされます。
/// `draw()` メソッドは毎フレーム呼ばれます。
///
/// ```swift
/// @main
/// final class MySketch: Sketch {
///     func draw() {
///         background(.black)
///         fill(.white)
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```
///
/// このプロトコルは `@MainActor` です。スケッチの外へアセットや状態を切り出す型
/// （シーン、アセット束、ゲーム状態など）を作るときは、**その型にも `@MainActor` を
/// 付けてください**。`loadImage` / `loadModel` / `loadSound` / `loadVideo` と、それらが
/// 返す ``MImage`` / ``Mesh`` / `SoundFile` / `VideoPlayer` のメンバーはすべて main actor
/// 隔離されており、素の `class` からは呼べません。
@MainActor
public protocol Sketch: AnyObject {
    /// 引数なしの新しいインスタンスを作成します（`@main` で必須）。
    init()

    /// スケッチの設定を返します（オプション）。
    var config: SketchConfig { get }

    /// 一度だけ実行される初期化処理（オプション）。
    func setup()

    /// 1フレームを描画します（描画メソッドを直接呼び出します）。
    func draw()

    /// 各フレームの前に GPU コンピュート処理を実行します（オプション）。
    func compute()

    // MARK: - Input Events (all optional)

    /// マウスボタン押下時に呼ばれます。
    func mousePressed()

    /// マウスボタン離し時に呼ばれます。
    func mouseReleased()

    /// マウス移動時に呼ばれます。
    func mouseMoved()

    /// マウスドラッグ時に呼ばれます。
    func mouseDragged()

    /// マウススクロール時に呼ばれます。
    func mouseScrolled()

    /// マウスクリック時（ドラッグなしの押下→離し）に呼ばれます。
    func mouseClicked()

    /// キー押下時に呼ばれます。
    func keyPressed()

    /// キー離し時に呼ばれます。
    func keyReleased()

    /// 文字入力を生成するキー押下時に呼ばれます（Processing の `keyTyped()` 互換）。
    ///
    /// 矢印・修飾キーなど文字を生成しないキーでは呼ばれません。
    /// キーリピートでも呼ばれます。
    func keyTyped()

    /// ファイルがウィンドウへドラッグ＆ドロップされた時に呼ばれます。
    ///
    /// - Parameter paths: ドロップされたファイルの絶対パスの配列。
    func fileDropped(_ paths: [String])

    // MARK: - State Preservation (optional)

    /// リロードをまたいで保持したい状態を返します（オプション）。
    ///
    /// `metaphor watch` は再ビルドのたびにスケッチのプロセスを作り直すため、既定では
    /// `draw()` が積み上げた状態が失われます。ここでスナップショットを返すと、
    /// 再起動後の ``restoreState(_:)`` に同じデータが渡されます。
    ///
    /// ```swift
    /// private struct SimState: Codable { var particles: [Particle] }
    ///
    /// func saveState() -> Data? { encodeState(SimState(particles: particles)) }
    /// func restoreState(_ data: Data) {
    ///     guard let s: SimState = decodeState(data) else { return }
    ///     particles = s.particles
    /// }
    /// ```
    ///
    /// 既定は `nil`（状態を保存しない）。時計（`frameCount` / `time`）の保持だけなら
    /// このメソッドは不要で、``SketchConfig/preserveClock`` を `true` にしてください。
    func saveState() -> Data?

    /// ``saveState()`` が返した状態を復元します（オプション）。
    ///
    /// `setup()` の**後**に一度だけ呼ばれます。デコードに失敗したら何もせず
    /// 初期状態のまま続けてください（開発ツールの都合でスケッチが壊れないように）。
    ///
    /// - Parameter data: 直前のプロセスが ``saveState()`` で返したデータ。
    func restoreState(_ data: Data)
}

// MARK: - Per-Instance Context (Pure Swift Storage)

/// Sketch → SketchContext マッピング用のストレージ（objc_getAssociatedObject の代替）。
///
/// キーは Sketch インスタンスへの weak 参照（ポインタ同一性）。Sketch が解放されると
/// エントリは自動的に purge されるため、SketchContext（renderer 一式）をプロセス終了
/// まで強参照し続けたり、解放後のアドレス再利用で新しいインスタンスが他人の stale
/// context を拾ったりしない（ObjectIdentifier キーの辞書はその両方が起きる）。
@MainActor
private let _sketchContextStorage = NSMapTable<AnyObject, SketchContext>(
    keyOptions: [.weakMemory, .objectPointerPersonality],
    valueOptions: .strongMemory
)

extension Sketch {
    /// このインスタンスに関連付けられたスケッチコンテキスト。
    /// SketchRunner のセットアップ時に設定されます。
    /// nil を代入するとストレージからエントリが削除されます（teardown 経路）。
    @MainActor
    internal var _context: SketchContext? {
        get { _sketchContextStorage.object(forKey: self) }
        set {
            if let newValue {
                _sketchContextStorage.setObject(newValue, forKey: self)
            } else {
                _sketchContextStorage.removeObject(forKey: self)
            }
        }
    }

    /// アクティブなコンテキスト。Runner の初期化前（または teardown 後）に
    /// 描画 API を呼ぶと明確なメッセージでクラッシュします。
    ///
    /// 失敗モードの方針（ADR-0005）: 描画系はここで fatalError（初期化前の呼び出しは
    /// プログラミングエラー）、`probe()` は無言 no-op（観測は本体挙動を変えない）、
    /// `pixels` は空バッファを返す（読み取り系はクラッシュより空が安全）。
    ///
    /// 後の 2 つは **この getter を経由しない**ことで成立している（`_context?` を直接読む）。
    /// context 未初期化でも `probe()` は黙り、`pixels` は空を返す（#356）。
    @MainActor
    public var context: SketchContext {
        guard let ctx = _context else {
            // 注: この検出は「Runner が context を初期化する前 / 破棄した後」のみ。
            // setup()/draw() の外（init やプロパティ初期化子など）での呼び出しが典型例。
            fatalError("[metaphor] Drawing APIs require an active SketchContext. This usually means the call happened before SketchRunner initialized the sketch (e.g. in init or a property initializer) or after teardown. Move the call into setup()/draw().")
        }
        return ctx
    }
}

// MARK: - Default Implementations

extension Sketch {
    public var config: SketchConfig { SketchConfig() }
    public func setup() {}
    public func draw() {}
    public func compute() {}
    public func mousePressed() {}
    public func mouseReleased() {}
    public func mouseMoved() {}
    public func mouseDragged() {}
    public func mouseScrolled() {}
    public func mouseClicked() {}
    public func keyPressed() {}
    public func keyReleased() {}
    public func keyTyped() {}
    public func fileDropped(_ paths: [String]) {}
    public func saveState() -> Data? { nil }
    public func restoreState(_ data: Data) {}
}

// MARK: - @main Entry Point

extension Sketch {
    /// スケッチアプリケーションを起動します（`@main` 属性から呼ばれます）。
    public static func main() {
        SketchRunner.run(sketchType: Self.self)
    }
}

// MARK: - PluginFactory

/// ``SketchConfig`` で使用するプラグインインスタンスを生成するファクトリ。
///
/// ``SketchConfig`` は `Sendable` であり、プラグインは参照型のため、
/// プラグインの生成はファクトリクロージャで遅延実行されます。
///
/// ```swift
/// var config: SketchConfig {
///     SketchConfig(
///         title: "My Sketch",
///         plugins: [
///             PluginFactory { MyPlugin() },
///             PluginFactory { NDIOutput(port: 5960) },
///         ]
///     )
/// }
/// ```
public struct PluginFactory: @unchecked Sendable {
    private let _create: @MainActor () -> MetaphorPlugin

    /// プラグインを生成するクロージャからファクトリを作成します。
    /// - Parameter create: 新しいプラグインインスタンスを返すクロージャ。
    public init(_ create: @MainActor @escaping () -> MetaphorPlugin) {
        self._create = create
    }

    /// プラグインをインスタンス化します。
    @MainActor
    public func create() -> MetaphorPlugin {
        _create()
    }
}

// MARK: - SketchConfig

/// スケッチのウィンドウ、キャンバス、レンダリング設定を構成します。
public struct SketchConfig: Sendable {
    /// オフスクリーンテクスチャの幅（ピクセル単位）。
    public var width: Int

    /// オフスクリーンテクスチャの高さ（ピクセル単位）。
    public var height: Int

    /// ウィンドウタイトル。
    public var title: String

    /// 目標フレームレート。
    public var fps: Int

    /// Syphon サーバー名（`nil` で Syphon 出力を無効化）。
    public var syphonName: String?

    /// Syphon 出力を有効化するか（既定 `false`）。
    ///
    /// `true` かつ ``syphonName`` が `nil` のとき、``title`` をサーバー名として Syphon を
    /// publish します（MadMapper 等のプロジェクションツールから安定した名前で参照可能）。
    /// 任意名にしたい場合は ``syphonName`` を指定してください（指定があれば Syphon は自動で
    /// 有効になります）。環境変数 `METAPHOR_SYPHON_NAME` があればそれが最優先されます。
    public var syphon: Bool

    /// ウィンドウサイズのスケール係数（ウィンドウサイズ = テクスチャサイズ × scale）。
    public var windowScale: Float

    /// フルスクリーンモードで起動するかどうか。
    public var fullScreen: Bool

    /// レンダーループモード。
    ///
    /// `.displayLink`（デフォルト）はディスプレイのリフレッシュレートに連動した
    /// 標準レンダリングです。`.timer(fps:)` はフレームタイミングを分離し、
    /// ウィンドウが隠れた際にレンダリングが停止しない Syphon 出力や
    /// 動画録画に適しています。
    public var renderLoopMode: RenderLoopMode

    /// スケッチ実行中に macOS の App Nap を抑止するか（既定 `true`）。
    ///
    /// App Nap はウィンドウが背面・オクルージョン状態のときタイマーを間引き QoS を
    /// 降格させるため、描画内容と無関係にフレームレートが大きく低下します
    /// （実測で最大 1/6）。既定ではスケッチ実行中に activity assertion を張り、
    /// バックグラウンドでも安定したフレームレートを維持します（システムの
    /// アイドルスリープも抑止されます）。バッテリー駆動などで省電力を優先したい
    /// 場合は `false` に設定してください。環境変数 `METAPHOR_ALLOW_APP_NAP=1` で
    /// 再コンパイルせずに App Nap を許可することもできます（環境変数が優先）。
    public var preventAppNap: Bool

    /// MSAA（マルチサンプルアンチエイリアス）のサンプル数（既定 `4`）。
    ///
    /// `1`（無効）/ `2` / `4` / `8` を指定します。デバイスが対応しないサンプル数は
    /// 警告を出力して `1` にフォールバックします。値を下げると描画品質と引き換えに
    /// GPU 負荷が下がります。
    public var msaa: Int

    /// リロードをまたいで時計（`frameCount` / `time`）を復元するか（既定 `false`）。
    ///
    /// `metaphor watch` の再ビルドで子プロセスが作り直されると、既定では
    /// `frameCount` が 0 に、`time` が 0 秒に戻ります。`true` にすると、
    /// 直前のプロセスが保存した時計を引き継いで再開します——**スケッチ側の
    /// コードはゼロ行**で、t 駆動のアニメーションが編集のたびに巻き戻りません。
    ///
    /// 既定を `false`（オプトイン）にしているのは、時刻が外部の都合で飛ぶことを
    /// 前提にしていないスケッチ（一定時間で終わる演出・録画）を驚かせないためです。
    /// ``Sketch/saveState()`` による状態の保存とは独立に使えます。
    public var preserveClock: Bool

    /// ファイルから読んだシェーダを保存のたびに自動リロードするか
    /// （既定は **DEBUG ビルドで `true`**、Release ビルドで `false`）。
    ///
    /// `loadShader()` / `createMaterialFromFile()` / `createPostEffectFromFile()` で読んだ
    /// `.metal` ファイルが監視され、保存するとビルド無しで再コンパイルされます（#648）。
    /// 書きかけの MSL でコンパイルに失敗しても**直前の動くシェーダのまま描き続け**、
    /// エラーだけがコンソールに出ます。
    ///
    /// 既定を Release で `false` にしているのは、作品として配布するビルドに
    /// ファイル監視スレッドを残さないためです。監視が起きるのはファイル由来の
    /// シェーダを実際に読んだときだけなので、使わないスケッチのコストはゼロです。
    /// 環境変数 `METAPHOR_SHADER_HOT_RELOAD`（`1` で有効・`0` で無効）があれば
    /// そちらが優先されます。
    public var shaderHotReload: Bool

    /// スケッチセットアップ時に登録するプラグインファクトリ。
    ///
    /// プラグインは ``Sketch/setup()`` が呼ばれる前にインスタンス化されスケッチに接続されます。
    /// ```swift
    /// var config: SketchConfig {
    ///     SketchConfig(plugins: [PluginFactory { MyPlugin() }])
    /// }
    /// ```
    public var plugins: [PluginFactory]

    /// 新しいスケッチ設定を作成します。
    ///
    /// - Parameters:
    ///   - width: オフスクリーンテクスチャの幅（ピクセル単位）。
    ///   - height: オフスクリーンテクスチャの高さ（ピクセル単位）。
    ///   - title: ウィンドウタイトル。
    ///   - fps: 目標フレームレート。
    ///   - syphonName: Syphon サーバー名（`nil` で無効化）。
    ///   - syphon: Syphon 出力を有効化するか（既定 `false`。`true` で ``title`` 名で publish）。
    ///   - windowScale: ウィンドウサイズのスケール係数。
    ///   - fullScreen: フルスクリーンモードで起動するかどうか。
    ///   - renderLoopMode: レンダーループモード（デフォルト: `.displayLink`）。
    ///   - preventAppNap: スケッチ実行中に App Nap を抑止するか（デフォルト: `true`）。
    ///   - msaa: MSAA サンプル数（デフォルト: `4`。`1` で無効、非対応値は `1` にフォールバック）。
    ///   - preserveClock: リロードをまたいで `frameCount` / `time` を復元するか（デフォルト: `false`）。
    ///   - shaderHotReload: シェーダファイルの自動リロード（デフォルト: DEBUG ビルドで `true`）。
    ///   - plugins: スケッチに登録するプラグインファクトリの配列。
    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        syphon: Bool = false,
        windowScale: Float = 0.5,
        fullScreen: Bool = false,
        renderLoopMode: RenderLoopMode = .displayLink,
        preventAppNap: Bool = true,
        msaa: Int = 4,
        preserveClock: Bool = false,
        shaderHotReload: Bool = SketchConfig.shaderHotReloadDefault,
        plugins: [PluginFactory] = []
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.syphon = syphon
        self.windowScale = windowScale
        self.fullScreen = fullScreen
        self.renderLoopMode = renderLoopMode
        self.preventAppNap = preventAppNap
        self.msaa = msaa
        self.preserveClock = preserveClock
        self.shaderHotReload = shaderHotReload
        self.plugins = plugins
    }

    /// ``shaderHotReload`` の既定値。DEBUG ビルドでのみ `true`。
    ///
    /// SwiftPM は依存パッケージも同じコンフィギュレーションでビルドするので、
    /// スケッチを `swift run`（debug）すれば有効・`swift build -c release` なら
    /// 無効、が再コンパイル無しで成り立ちます。
    public static var shaderHotReloadDefault: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
