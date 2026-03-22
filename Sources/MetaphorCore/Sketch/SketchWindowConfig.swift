/// セカンダリスケッチウィンドウの設定。
///
/// ``SketchWindow`` と共に使用し、セカンダリウィンドウのレンダー解像度、
/// ウィンドウタイトル、フレームレート、オプションの Syphon 出力を定義します。
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

    /// Syphon サーバー名。Syphon 出力を無効にするには `nil`。
    public var syphonName: String?

    /// レンダーループモード。
    ///
    /// デフォルトは ``RenderLoopMode/displayLink``。``syphonName`` が設定されており
    /// `.displayLink` のままの場合、信頼性のある Syphon 出力のために自動的に
    /// ``RenderLoopMode/timer(fps:)`` に切り替わります。
    public var renderLoopMode: RenderLoopMode = .displayLink

    /// 新しいセカンダリウィンドウ設定を作成します。
    ///
    /// - Parameters:
    ///   - width: オフスクリーンレンダーテクスチャの幅（ピクセル単位）。
    ///   - height: オフスクリーンレンダーテクスチャの高さ（ピクセル単位）。
    ///   - title: ウィンドウタイトル。
    ///   - fps: 目標フレームレート。
    ///   - windowScale: ウィンドウのスケール係数。
    ///   - syphonName: Syphon サーバー名。無効にするには `nil`。
    ///   - renderLoopMode: レンダーループモード（デフォルト: `.displayLink`）。
    public init(
        width: Int = 800,
        height: Int = 600,
        title: String = "metaphor",
        fps: Int = 60,
        windowScale: Float = 1.0,
        syphonName: String? = nil,
        renderLoopMode: RenderLoopMode = .displayLink
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.windowScale = windowScale
        self.syphonName = syphonName
        self.renderLoopMode = renderLoopMode
    }
}
