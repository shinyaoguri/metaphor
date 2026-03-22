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
@MainActor
private var _sketchContextStorage: [ObjectIdentifier: SketchContext] = [:]

extension Sketch {
    /// このインスタンスに関連付けられたスケッチコンテキスト。
    /// SketchRunner のセットアップ時に設定されます。
    @MainActor
    internal var _context: SketchContext? {
        get { _sketchContextStorage[ObjectIdentifier(self)] }
        set {
            if let newValue {
                _sketchContextStorage[ObjectIdentifier(self)] = newValue
            } else {
                _sketchContextStorage.removeValue(forKey: ObjectIdentifier(self))
            }
        }
    }

    /// アクティブなコンテキスト。setup()/draw() 外で呼ぶと明確なメッセージでクラッシュします。
    @MainActor
    public var context: SketchContext {
        guard let ctx = _context else {
            fatalError("[metaphor] Drawing methods cannot be called outside setup()/draw(). Ensure SketchRunner has initialized the context.")
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
    ///   - windowScale: ウィンドウサイズのスケール係数。
    ///   - fullScreen: フルスクリーンモードで起動するかどうか。
    ///   - renderLoopMode: レンダーループモード（デフォルト: `.displayLink`）。
    ///   - plugins: スケッチに登録するプラグインファクトリの配列。
    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5,
        fullScreen: Bool = false,
        renderLoopMode: RenderLoopMode = .displayLink,
        plugins: [PluginFactory] = []
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
        self.fullScreen = fullScreen
        self.renderLoopMode = renderLoopMode
        self.plugins = plugins
    }
}
