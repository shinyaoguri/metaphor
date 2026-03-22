import AppKit

extension SketchContext {

    // MARK: - Image

    /// 指定したファイルパスから画像を読み込みます。
    /// - Parameter path: 画像のファイルパス。
    /// - Returns: 読み込まれた画像。
    public func loadImage(_ path: String) throws -> MImage {
        try MImage(path: path, device: renderer.device)
    }

    /// ピクセル操作用の空の画像を作成します。
    /// - Parameters:
    ///   - width: 画像の幅（ピクセル単位）。
    ///   - height: 画像の高さ（ピクセル単位）。
    /// - Returns: 新しい空白画像。失敗時は nil。
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        MImage.createImage(width, height, device: renderer.device)
    }

    /// 画像に GPU 画像フィルターを適用します。
    /// - Parameters:
    ///   - image: 対象の画像。
    ///   - type: 適用するフィルタータイプ。
    public func filter(_ image: MImage, _ type: FilterType) {
        renderer.imageFilterGPU.apply(type, to: image)
    }

    /// オフスクリーン 2D 描画バッファを作成します。
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい Graphics インスタンス。失敗時は nil。
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        try? Graphics(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    /// オフスクリーン 3D 描画バッファを作成します。
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい Graphics3D インスタンス。失敗時は nil。
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        try? Graphics3D(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    // MARK: - Camera Capture

    /// カメラキャプチャデバイスを作成し自動的にキャプチャを開始します。
    /// - Parameters:
    ///   - width: キャプチャ幅（ピクセル単位、デフォルト 1280）。
    ///   - height: キャプチャ高さ（ピクセル単位、デフォルト 720）。
    ///   - position: カメラの位置（デフォルト `.front`）。
    /// - Returns: 開始済みの `CaptureDevice` インスタンス。
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, position: position)
        capture.start()
        return capture
    }

    /// キャプチャデバイスの最新フレームを指定位置に描画します。
    /// - Parameters:
    ///   - capture: キャプチャデバイス。
    ///   - x: 左上角の x 座標。
    ///   - y: 左上角の y 座標。
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y)
        }
    }

    /// キャプチャデバイスの最新フレームを明示的なサイズで描画します。
    /// - Parameters:
    ///   - capture: キャプチャデバイス。
    ///   - x: 左上角の x 座標。
    ///   - y: 左上角の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y, w, h)
        }
    }

    /// 画像を指定位置に描画します。
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        canvas.image(img, x, y)
    }

    /// Graphics バッファを指定位置に描画します。
    /// - Parameters:
    ///   - pg: オフスクリーングラフィックスバッファ。
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Graphics バッファを明示的なサイズで描画します。
    /// - Parameters:
    ///   - pg: オフスクリーングラフィックスバッファ。
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Graphics3D バッファを指定位置に描画します。
    /// - Parameters:
    ///   - pg: オフスクリーン 3D グラフィックスバッファ。
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Graphics3D バッファを明示的なサイズで描画します。
    /// - Parameters:
    ///   - pg: オフスクリーン 3D グラフィックスバッファ。
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// 画像を明示的なサイズで描画します。
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
    }

    /// 画像のサブ領域を描画します（スプライトシートやタイルマップ用）。
    /// - Parameters:
    ///   - img: ソース画像。
    ///   - dx: 描画先の x 座標。
    ///   - dy: 描画先の y 座標。
    ///   - dw: 描画先の幅。
    ///   - dh: 描画先の高さ。
    ///   - sx: ソースの x 座標。
    ///   - sy: ソースの y 座標。
    ///   - sw: ソースの幅。
    ///   - sh: ソースの高さ。
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        canvas.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: - Text

    /// テキストレンダリングのサイズを設定します。
    /// - Parameter size: フォントサイズ（ポイント単位）。
    public func textSize(_ size: Float) {
        canvas.textSize(size)
    }

    /// テキストレンダリングのフォントファミリーを設定します。
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) {
        canvas.textFont(family)
    }

    /// テキストの配置を設定します。
    /// - Parameters:
    ///   - horizontal: 水平方向の配置。
    ///   - vertical: 垂直方向の配置（デフォルト `.baseline`）。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// 複数行テキストの行間を設定します。
    /// - Parameter leading: 行の高さ（ピクセル単位）。
    public func textLeading(_ leading: Float) {
        canvas.textLeading(leading)
    }

    /// 文字列のレンダリング幅を計算します。
    /// - Parameter string: 計測するテキスト。
    /// - Returns: 幅（ピクセル単位）。
    public func textWidth(_ string: String) -> Float {
        canvas.textWidth(string)
    }

    /// 現在のテキスト設定でのフォントアセントを返します。
    /// - Returns: アセント値（ピクセル単位）。
    public func textAscent() -> Float {
        canvas.textAscent()
    }

    /// 現在のテキスト設定でのフォントディセントを返します。
    /// - Returns: ディセント値（ピクセル単位）。
    public func textDescent() -> Float {
        canvas.textDescent()
    }

    /// 指定位置にテキストを描画します。
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func text(_ string: String, _ x: Float, _ y: Float) {
        canvas.text(string, x, y)
    }

    /// バウンディングボックス内に自動折り返し付きでテキストを描画します。
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: ボックスの x 座標。
    ///   - y: ボックスの y 座標。
    ///   - w: ボックスの幅。
    ///   - h: ボックスの高さ。
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.text(string, x, y, w, h)
    }

    // MARK: - Screenshot

    /// 指定したファイルパスにスクリーンショットを保存します。
    /// - Parameter path: 出力ファイルパス。
    public func save(_ path: String) {
        renderer.saveScreenshot(to: path)
    }

    /// フレーム連番エクスポートを開始します。
    /// - Parameters:
    ///   - directory: 出力ディレクトリ（nil の場合はデスクトップに自動生成）。
    ///   - pattern: フレーム番号プレースホルダー付きのファイル名パターン。
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        let dir: String
        if let directory {
            dir = directory
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            dir = NSHomeDirectory() + "/Desktop/metaphor_frames_\(formatter.string(from: Date()))"
        }
        renderer.frameExporter.beginSequence(directory: dir, pattern: pattern)
    }

    /// フレーム連番エクスポートを停止します。
    public func endRecord() {
        renderer.frameExporter.endSequence()
    }

    /// 動画録画を開始します。
    /// - Parameters:
    ///   - path: 出力ファイルパス（nil の場合はデスクトップに自動生成）。
    ///   - config: 動画エクスポート設定。
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).\(config.format.fileExtension)"
        }
        try? renderer.videoExporter.beginRecord(
            path: actualPath,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height,
            config: config
        )
    }

    /// 動画録画を終了します。
    /// - Parameter completion: 書き込み完了時に呼ばれるコールバック。
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        renderer.videoExporter.endRecord(completion: completion)
    }

    /// 動画録画を非同期で終了します。
    public func endVideoRecord() async {
        await renderer.videoExporter.endRecord()
    }

    /// 現在のフレームを単一画像ファイルとして保存します（Processing 互換）。
    /// - Parameter filename: 出力ファイル名（nil の場合は番号付き名前を自動生成）。
    public func saveFrame(_ filename: String? = nil) {
        let name: String
        if let filename {
            name = filename
        } else {
            name = "screen-\(String(format: "%04d", frameCount)).png"
        }
        let path = NSHomeDirectory() + "/Desktop/" + name
        renderer.saveScreenshot(to: path)
    }

    /// タイムスタンプ付きスクリーンショットをデスクトップに保存します。
    public func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "metaphor_\(formatter.string(from: Date())).png"
        let path = NSHomeDirectory() + "/Desktop/" + name
        save(path)
    }

    // MARK: - Offline Rendering

    /// オフラインレンダリングモードがアクティブかどうかを示します。
    public var isOfflineRendering: Bool {
        renderer.isOfflineRendering
    }

    /// オフラインレンダリングモードを開始します。
    ///
    /// 経過時間が決定論的になり、フレーム落ちのない高品質な
    /// 動画レンダリングが可能になります。
    /// - Parameter fps: 目標フレームレート（デフォルト 60）。
    public func beginOfflineRender(fps: Double = 60) {
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = fps
        renderer.resetOfflineRendering()
    }

    /// オフラインレンダリングモードを終了します。
    public func endOfflineRender() {
        renderer.isOfflineRendering = false
    }

    // MARK: - FBO Feedback

    /// フレームバッファフィードバックを有効にします。
    ///
    /// 有効にすると、各フレームの開始時に前フレームのカラーテクスチャがコピーされ、
    /// ``previousFrame()`` で `MImage` として取得できます。
    public func enableFeedback() {
        renderer.feedbackEnabled = true
    }

    /// フレームバッファフィードバックを無効にします。
    public func disableFeedback() {
        renderer.feedbackEnabled = false
    }

    /// 前フレームのレンダリング結果を画像として返します。
    ///
    /// このメソッドを使用する前に ``enableFeedback()`` を呼び出してください。
    /// フィードバックが無効の場合や最初のフレームでは nil を返します。
    /// - Returns: 前フレームの `MImage`。または nil。
    public func previousFrame() -> MImage? {
        guard let tex = renderer.previousFrameTexture else { return nil }
        return MImage(texture: tex)
    }
}
