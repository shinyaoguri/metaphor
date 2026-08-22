/// セカンダリスケッチウィンドウの設定。
///
/// ``SketchWindow`` と共に使用し、セカンダリウィンドウのレンダー解像度、
/// ウィンドウタイトル、フレームレート、このウィンドウ専用のプラグインを定義します。
///
/// ```swift
/// let config = SketchWindowConfig(
///     width: 400,
///     height: 300,
///     title: "Preview"
/// )
/// let window = createWindow(config)
/// ```
public struct SketchWindowConfig: Sendable {
    /// オフスクリーンレンダーテクスチャの幅（ピクセル単位）。
    public var width: Int

    /// オフスクリーンレンダーテクスチャの高さ（ピクセル単位）。
    public var height: Int

    /// ウィンドウタイトル。
    public var title: String

    /// 目標フレームレート。
    public var fps: Int

    /// ウィンドウのスケール係数（ウィンドウサイズ = テクスチャサイズ × scale）。
    public var windowScale: Float

    /// 旧 ``syphonName`` の実体（deprecation 窓の間だけ。ADR-0014 / #1040。
    /// `SketchConfig.legacySyphonName` と同じ理由で internal・非 deprecated）。
    var legacySyphonName: String?

    /// Syphon サーバー名。Syphon 出力を無効にするには `nil`。
    ///
    /// **Deprecated**: Syphon は別パッケージ `metaphor-syphon` へ移りました（ADR-0014）。
    /// ``plugins`` に `.syphon(name:)` を渡してください。移行期間中は metaphor-syphon の
    /// provider がこの値も読みます。
    @available(*, deprecated, message: "Syphon moved to the metaphor-syphon package: add it to Package.swift and pass plugins: [.syphon(name:)]")
    public var syphonName: String? {
        get { legacySyphonName }
        set { legacySyphonName = newValue }
    }

    /// レンダーループモード。
    ///
    /// デフォルトは ``RenderLoopMode/displayLink``。``PluginRequirements/externalRenderLoop`` を
    /// 宣言するプラグインや出力（Syphon 等）があり `.displayLink` のままの場合、出力の安定のため
    /// 自動的に ``RenderLoopMode/timer(fps:)`` に切り替わります。
    public var renderLoopMode: RenderLoopMode = .displayLink

    /// このウィンドウのレンダラーに登録するプラグインファクトリ（既定は空）。
    ///
    /// プライマリの ``SketchConfig/plugins`` と同じ型で、ウィンドウ生成時にインスタンス化されて
    /// このウィンドウ専用のレンダラーへ接続されます（プライマリのプラグインとは独立）。
    /// ``PluginRequirements/externalRenderLoop`` を宣言するファクトリがあれば、``renderLoopMode`` が
    /// `.displayLink` のままでもタイマー駆動に切り替わります。
    public var plugins: [PluginFactory] = []

    /// 新しいセカンダリウィンドウ設定を作成します。
    ///
    /// - Parameters:
    ///   - width: オフスクリーンレンダーテクスチャの幅（ピクセル単位）。
    ///   - height: オフスクリーンレンダーテクスチャの高さ（ピクセル単位）。
    ///   - title: ウィンドウタイトル。
    ///   - fps: 目標フレームレート。
    ///   - windowScale: ウィンドウのスケール係数。
    ///   - renderLoopMode: レンダーループモード（デフォルト: `.displayLink`）。
    ///   - plugins: このウィンドウのレンダラーに登録するプラグインファクトリ（デフォルト: 空。Syphon は metaphor-syphon の `.syphon(name:)`）。
    public init(
        width: Int = 800,
        height: Int = 600,
        title: String = "metaphor",
        fps: Int = 60,
        windowScale: Float = 1.0,
        renderLoopMode: RenderLoopMode = .displayLink,
        plugins: [PluginFactory] = []
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.windowScale = windowScale
        self.legacySyphonName = nil
        self.renderLoopMode = renderLoopMode
        self.plugins = plugins
    }

    /// `syphonName:` を取る旧 init（deprecated）。`syphonName` に既定値が無いのは新しい init との曖昧さを断つため。
    @available(*, deprecated, message: "Syphon moved to the metaphor-syphon package: add it to Package.swift and pass plugins: [.syphon(name:)]")
    public init(
        width: Int = 800,
        height: Int = 600,
        title: String = "metaphor",
        fps: Int = 60,
        windowScale: Float = 1.0,
        syphonName: String?,
        renderLoopMode: RenderLoopMode = .displayLink,
        plugins: [PluginFactory] = []
    ) {
        self.init(
            width: width, height: height, title: title, fps: fps, windowScale: windowScale,
            renderLoopMode: renderLoopMode, plugins: plugins
        )
        self.legacySyphonName = syphonName
    }
}
