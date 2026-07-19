import AppKit
@preconcurrency import Metal

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
    /// 失敗モードの方針: 描画系はここで fatalError（初期化前の呼び出しはプログラミング
    /// エラー）、`probe()` は無言 no-op（観測は本体挙動を変えない）、`pixels` は
    /// 空バッファを返す（読み取り系はクラッシュより空が安全）。
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
}

// MARK: - Deprecated

extension Sketch {
    /// 明示的なコンテキストパラメータを使用して1フレームを描画します。
    ///
    /// - Parameter ctx: スケッチコンテキスト。
    @available(*, deprecated, message: "Use draw() instead. Access context via self properties or self._context.")
    public func draw(_ ctx: SketchContext) { draw() }
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
        self.plugins = plugins
    }
}
