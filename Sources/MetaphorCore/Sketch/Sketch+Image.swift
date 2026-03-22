// MARK: - Image, Text, Recording, Feedback

extension Sketch {

    // MARK: Image

    /// 指定したファイルパスから画像を読み込みます。
    ///
    /// - Parameter path: 画像のファイルパス。
    /// - Returns: 読み込まれた画像。
    public func loadImage(_ path: String) throws -> MImage {
        try context.loadImage(path)
    }

    /// 画像を非同期で読み込みます（ファイル I/O をメインスレッド外で実行）。
    ///
    /// - Parameter path: 画像のファイルパス。
    /// - Returns: 読み込まれた画像。
    public func loadImageAsync(_ path: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(path: path)
    }

    /// 名前付き画像リソースを非同期で読み込みます。
    ///
    /// - Parameter name: 画像リソースの名前。
    /// - Returns: 読み込まれた画像。
    public func loadImageAsync(named name: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(named: name)
    }

    /// 指定したサイズの空白画像を作成します。
    ///
    /// - Parameters:
    ///   - width: 画像の幅（ピクセル単位）。
    ///   - height: 画像の高さ（ピクセル単位）。
    /// - Returns: 新しい空白画像。作成に失敗した場合は `nil`。
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        context.createImage(width, height)
    }

    /// 2D オフスクリーングラフィックスバッファを作成します。
    ///
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい ``Graphics`` インスタンス。作成に失敗した場合は `nil`。
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        context.createGraphics(w, h)
    }

    /// 3D オフスクリーングラフィックスバッファを作成します。
    ///
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい ``Graphics3D`` インスタンス。作成に失敗した場合は `nil`。
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        context.createGraphics3D(w, h)
    }

    /// カメラキャプチャデバイスを作成します。
    ///
    /// - Parameters:
    ///   - width: キャプチャ幅（ピクセル単位）。
    ///   - height: キャプチャ高さ（ピクセル単位）。
    ///   - position: カメラの位置（前面または背面）。
    /// - Returns: 新しい ``CaptureDevice`` インスタンス。作成に失敗した場合は `nil`。
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice? {
        context.createCapture(width: width, height: height, position: position)
    }

    /// キャプチャデバイスの最新フレームを指定位置に描画します。
    ///
    /// - Parameters:
    ///   - capture: 描画元のキャプチャデバイス。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        context.image(capture, x, y)
    }

    /// キャプチャデバイスの最新フレームを指定位置・サイズで描画します。
    ///
    /// - Parameters:
    ///   - capture: 描画元のキャプチャデバイス。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(capture, x, y, w, h)
    }

    /// 2D オフスクリーングラフィックスバッファを指定位置に描画します。
    ///
    /// - Parameters:
    ///   - pg: 描画するグラフィックスバッファ。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// 2D オフスクリーングラフィックスバッファを指定位置・サイズで描画します。
    ///
    /// - Parameters:
    ///   - pg: 描画するグラフィックスバッファ。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// 3D オフスクリーングラフィックスバッファを指定位置に描画します。
    ///
    /// - Parameters:
    ///   - pg: 描画する 3D グラフィックスバッファ。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        context.image(pg, x, y)
    }

    /// 3D オフスクリーングラフィックスバッファを指定位置・サイズで描画します。
    ///
    /// - Parameters:
    ///   - pg: 描画する 3D グラフィックスバッファ。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(pg, x, y, w, h)
    }

    /// 画像を指定位置に描画します。
    ///
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        context.image(img, x, y)
    }

    /// 画像を指定位置・サイズで描画します。
    ///
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: 描画位置の x 座標。
    ///   - y: 描画位置の y 座標。
    ///   - w: 表示幅。
    ///   - h: 表示高さ。
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.image(img, x, y, w, h)
    }

    /// 画像のサブ領域を描画します（スプライトシートやタイルマップ用）。
    ///
    /// - Parameters:
    ///   - img: ソース画像。
    ///   - dx: 描画先の x 座標。
    ///   - dy: 描画先の y 座標。
    ///   - dw: 描画先の幅。
    ///   - dh: 描画先の高さ。
    ///   - sx: ソース領域の x 座標。
    ///   - sy: ソース領域の y 座標。
    ///   - sw: ソース領域の幅。
    ///   - sh: ソース領域の高さ。
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        context.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: Text

    /// 以降のテキスト描画のテキストサイズを設定します。
    ///
    /// - Parameter size: フォントサイズ（ポイント単位）。
    public func textSize(_ size: Float) {
        context.textSize(size)
    }

    /// 以降のテキスト描画のフォントファミリーを設定します。
    ///
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) {
        context.textFont(family)
    }

    /// テキストの配置を設定します。
    ///
    /// - Parameters:
    ///   - horizontal: 水平方向の配置。
    ///   - vertical: 垂直方向の配置。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        context.textAlign(horizontal, vertical)
    }

    /// 複数行テキストの行間を設定します。
    ///
    /// - Parameter leading: 行の高さ（ピクセル単位）。
    public func textLeading(_ leading: Float) {
        context.textLeading(leading)
    }

    /// 指定位置にテキスト文字列を描画します。
    ///
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func text(_ string: String, _ x: Float, _ y: Float) {
        context.text(string, x, y)
    }

    /// バウンディングボックス内にテキスト文字列を描画します。
    ///
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: バウンディングボックスの x 座標。
    ///   - y: バウンディングボックスの y 座標。
    ///   - w: バウンディングボックスの幅。
    ///   - h: バウンディングボックスの高さ。
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.text(string, x, y, w, h)
    }

    /// 現在のフォント設定でテキスト文字列の幅を計算します。
    ///
    /// - Parameter string: 計測するテキスト。
    /// - Returns: テキストの幅（ピクセル単位）。
    public func textWidth(_ string: String) -> Float {
        context.textWidth(string)
    }

    /// 現在のフォントのアセント値を返します。
    ///
    /// - Returns: アセント値（ピクセル単位）。
    public func textAscent() -> Float {
        context.textAscent()
    }

    /// 現在のフォントのディセント値を返します。
    ///
    /// - Returns: ディセント値（ピクセル単位）。
    public func textDescent() -> Float {
        context.textDescent()
    }

    // MARK: Screenshot & Recording

    /// 現在のフレームを指定したファイルパスに保存します。
    ///
    /// - Parameter path: 出力ファイルパス。
    public func save(_ path: String) {
        context.save(path)
    }

    /// 現在のフレームをデフォルトの場所に保存します。
    public func save() {
        context.save()
    }

    /// フレーム連番の画像ファイルとしての記録を開始します。
    ///
    /// - Parameters:
    ///   - directory: 出力ディレクトリ（`nil` の場合はデフォルトを使用）。
    ///   - pattern: フレーム番号プレースホルダー付きのファイル名パターン。
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        context.beginRecord(directory: directory, pattern: pattern)
    }

    /// フレーム連番の記録を停止します。
    public func endRecord() {
        context.endRecord()
    }

    /// 単一フレームを画像ファイルに保存します。
    ///
    /// - Parameter filename: 出力ファイル名（`nil` の場合は自動生成）。
    public func saveFrame(_ filename: String? = nil) {
        context.saveFrame(filename)
    }

    // MARK: Video Recording

    /// 動画出力の録画を開始します。
    ///
    /// - Parameters:
    ///   - path: 出力ファイルパス（`nil` の場合は自動生成）。
    ///   - config: 動画エクスポート設定。
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        context.beginVideoRecord(path, config: config)
    }

    /// 動画の録画を停止しファイルを完成させます。
    ///
    /// - Parameter completion: 書き込み完了時に呼ばれるオプションのコールバック。
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        context.endVideoRecord(completion: completion)
    }

    /// 動画の録画を非同期で停止しファイルを完成させます。
    public func endVideoRecord() async {
        await context.endVideoRecord()
    }

    // MARK: Offline Rendering

    /// オフラインレンダリングモードがアクティブかどうかを示します。
    public var isOfflineRendering: Bool {
        context.isOfflineRendering
    }

    /// 決定論的タイミングのオフラインレンダリングモードを有効にします。
    ///
    /// - Parameter fps: 時間計算に使用する仮想フレームレート。
    public func beginOfflineRender(fps: Double = 60) {
        context.beginOfflineRender(fps: fps)
    }

    /// オフラインレンダリングモードを無効にしリアルタイムタイミングに戻します。
    public func endOfflineRender() {
        context.endOfflineRender()
    }

    // MARK: FBO Feedback

    /// フレームバッファフィードバック（前フレームアクセス）を有効にします。
    public func enableFeedback() {
        context.enableFeedback()
    }

    /// フレームバッファフィードバックを無効にします。
    public func disableFeedback() {
        context.disableFeedback()
    }

    /// 前フレームのレンダリング結果を取得します。
    ///
    /// - Returns: 前フレームの ``MImage``。フィードバックが無効の場合は `nil`。
    public func previousFrame() -> MImage? {
        context.previousFrame()
    }
}
