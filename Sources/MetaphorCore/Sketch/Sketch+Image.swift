// MARK: - Image, Text, Recording, Feedback

extension Sketch {

    // MARK: Image

    /// 指定したファイルパスから画像を読み込みます。
    ///
    /// 既定でパスキーのキャッシュが効き、同じパスの再読込は同一の ``MImage``
    /// インスタンスを返します（`draw()` 内で呼んでも毎フレームの再デコードは
    /// 起きません）。独立したコピーが必要な場合は `cache: false` を指定します。
    ///
    /// - Parameters:
    ///   - path: 画像のファイルパス。
    ///   - cache: キャッシュを使うか（既定 true）。
    /// - Returns: 読み込まれた画像。
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   指定されたパスからテクスチャを読み込めない場合（不在・非対応フォーマット・I/O エラー）。
    public func loadImage(_ path: String, cache: Bool = true) throws -> MImage {
        try context.loadImage(path, cache: cache)
    }

    /// 画像を非同期で読み込みます（ファイル I/O をメインスレッド外で実行）。
    ///
    /// - Parameters:
    ///   - path: 画像のファイルパス。
    ///   - cache: キャッシュを使うか（既定 true）。
    /// - Returns: 読み込まれた画像。
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   指定されたパスからテクスチャを読み込めない場合（不在・非対応フォーマット・I/O エラー）。
    public func loadImageAsync(_ path: String, cache: Bool = true) async throws -> MImage {
        try await context.loadImageAsync(path, cache: cache)
    }

    /// 名前付き画像リソースを非同期で読み込みます。
    ///
    /// - Parameter name: 画像リソースの名前。
    /// - Returns: 読み込まれた画像。
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   名前付きリソースが見つからないか読み込めない場合。
    public func loadImageAsync(named name: String) async throws -> MImage {
        try await context.resourceLoader.loadImageAsync(named: name)
    }

    /// テキストのグリフアウトラインを、輪郭ごとの閉じたポリラインとして返します。
    ///
    /// 現在の ``textSize(_:)`` / ``textFont(_:)-(String)`` / ``textAlign(_:_:)`` を
    /// `text()` と同じように解釈するため、同じ引数で呼べば描画結果と同じ位置の輪郭が
    /// 得られます。文字の穴（`o` の内側など）も 1 本の輪郭として返ります。
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - x: テキストの x 座標（`text()` と同じ意味）。
    ///   - y: テキストの y 座標（`text()` と同じ意味）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: 輪郭ごとのポリライン。
    public func textToContours(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [[Vec2]] {
        context.textToContours(string, x, y, sampleFactor: sampleFactor)
    }

    /// テキストのグリフアウトライン上の点を 1 本の配列で返します（p5 の `textToPoints` 相当）。
    ///
    /// 輪郭の区切りは失われます。文字を粒子や図形の配置元として使うときに向きます。
    ///
    /// ```swift
    /// for p in textToPoints("metaphor", 40, 200) {
    ///     circle(p.x, p.y, 4)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - x: テキストの x 座標（`text()` と同じ意味）。
    ///   - y: テキストの y 座標（`text()` と同じ意味）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: アウトライン上の点。
    public func textToPoints(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [Vec2] {
        context.textToPoints(string, x, y, sampleFactor: sampleFactor)
    }

    /// テキストのアウトラインを、穴つきで描けるリテインドシェイプへ変換します。
    ///
    /// 返るのは外周ごとの子を持つグループシェイプ。`o` の内側のような穴はコンターとして
    /// 子に載るため、``shape(_:_:_:)`` でそのまま塗り分けられます。
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - x: テキストの x 座標（`text()` と同じ意味）。
    ///   - y: テキストの y 座標（`text()` と同じ意味）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: 現在のスタイルをキャプチャしたグループシェイプ。
    public func textToShape(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> MShape {
        context.textToShape(string, x, y, sampleFactor: sampleFactor)
    }

    /// 指定したファイルパスからフォントを読み込みます。
    ///
    /// フォントは現在のプロセスにだけ登録されます（システムのフォント設定は変更しません）。
    /// 返された ``MFont`` を ``textFont(_:)-(MFont)`` へ渡すと、以降のテキスト描画・計測が
    /// そのフォントで行われます。既定でパスキーのキャッシュが効くため、`draw()` 内で
    /// 呼んでも毎フレームの再登録は起きません。
    ///
    /// ```swift
    /// func setup() {
    ///     guard let path = Bundle.module.path(
    ///         forResource: "SpaceMono-Regular", ofType: "ttf", inDirectory: "Resources")
    ///     else { return }
    ///     textFont(try! loadFont(path))
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: フォントファイル（`.ttf` / `.otf` / `.ttc` / `.otc` / `.dfont`）のパス。
    ///   - cache: キャッシュを使うか（既定 true）。
    /// - Returns: 読み込まれたフォント。
    /// - Throws: ``MetaphorError/font(_:)``。ファイルが無い場合は
    ///   ``MetaphorError/FontFailure/fileNotFound(path:)``、フォントとして読めない場合は
    ///   ``MetaphorError/FontFailure/noFontsInFile(path:)``、登録に失敗した場合は
    ///   ``MetaphorError/FontFailure/registrationFailed(path:detail:)``。
    public func loadFont(_ path: String, cache: Bool = true) throws -> MFont {
        try context.loadFont(path, cache: cache)
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

    /// 画像に GPU 画像フィルタを適用します（in-place）。
    ///
    /// レンダラのコンピュートパイプライン上で処理するため、CPU 版の
    /// ``MImage/filter(_:)`` よりも高速です。使い分け:
    ///
    /// - **GPU 版（本メソッド）**: スケッチ実行中（レンダラが生きている文脈）で使う。
    ///   毎フレーム適用するような用途はこちら。
    /// - **CPU 版 ``MImage/filter(_:)``**: レンダラを必要としないため、スケッチ外や
    ///   単体画像の一括処理に使える。`loadPixels()` → 処理 → `updatePixels()` を
    ///   まとめて実行する。
    ///
    /// - Parameters:
    ///   - image: 対象の画像（内容が書き換わります）。
    ///   - type: 適用するフィルタタイプ。
    public func filter(_ image: MImage, _ type: FilterType) {
        context.filter(image, type)
    }

    /// キャンバスの矩形領域を別の矩形領域へコピーします（Processing の `copy()` 互換）。
    ///
    /// コピー元はオフスクリーンレンダーターゲットの現在の内容（前フレームまでの
    /// 描画結果）。サイズが異なる場合は拡縮されます。`imageMode`/`tint` の影響を
    /// 受けない絶対座標で描かれます。
    ///
    /// - Parameters:
    ///   - sx: コピー元矩形の x（ピクセル）。
    ///   - sy: コピー元矩形の y（ピクセル）。
    ///   - sw: コピー元矩形の幅（ピクセル）。
    ///   - sh: コピー元矩形の高さ（ピクセル）。
    ///   - dx: コピー先矩形の x（ピクセル）。
    ///   - dy: コピー先矩形の y（ピクセル）。
    ///   - dw: コピー先矩形の幅（ピクセル）。
    ///   - dh: コピー先矩形の高さ（ピクセル）。
    public func copy(
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float
    ) {
        context.copy(sx, sy, sw, sh, dx, dy, dw, dh)
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

    /// 接続中のカメラを列挙します。
    ///
    /// 内蔵カメラ・外付け（USB）カメラ・Continuity Camera・デスクビューカメラが
    /// 対象です。取得した ``CaptureDeviceInfo`` を ``createCapture(width:height:device:)``
    /// へ渡すことで、複数カメラ環境で使用するカメラを明示的に選択できます。
    ///
    /// ```swift
    /// for cam in listCaptureDevices() {
    ///     print(cam.name, cam.kind)
    /// }
    /// ```
    ///
    /// - Returns: 接続中のカメラの一覧（接続がなければ空配列）。
    public func listCaptureDevices() -> [CaptureDeviceInfo] {
        context.listCaptureDevices()
    }

    /// カメラキャプチャデバイスを作成し、**自動的にキャプチャを開始**します
    /// （`start()` を呼ぶ必要はありません。停止するには `stop()`）。
    ///
    /// - Note: カメラ権限が拒否されている場合は `isAvailable == false` の
    ///   デバイスが返ります。使用中のカメラの切断は
    ///   ``CaptureDevice/onDisconnect`` で検知できます。
    ///
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（デフォルト 1280）。最も近い対応解像度が
    ///     選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（デフォルト 720）。
    ///   - position: 使用するカメラ位置。`nil`（デフォルト）の場合は
    ///     ユーザー/システムの優先カメラを使用します。macOS ではほとんどの
    ///     カメラが位置情報を持たないため、特定のカメラを選ぶには
    ///     ``createCapture(width:height:device:)`` を使用してください。
    /// - Returns: 開始済みのキャプチャデバイス。
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition? = nil) -> CaptureDevice {
        context.createCapture(width: width, height: height, position: position)
    }

    /// 指定したカメラでキャプチャデバイスを作成し、**自動的にキャプチャを開始**します。
    ///
    /// ```swift
    /// if let external = listCaptureDevices().first(where: { $0.kind == .external }) {
    ///     capture = createCapture(device: external)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（デフォルト 1280）。最も近い対応解像度が
    ///     選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（デフォルト 720）。
    ///   - device: ``listCaptureDevices()`` で取得したデバイス情報。
    ///     既に切断されている場合は `isAvailable == false` のデバイスが返ります。
    /// - Returns: 開始済みのキャプチャデバイス。
    public func createCapture(width: Int = 1280, height: Int = 720, device: CaptureDeviceInfo) -> CaptureDevice {
        context.createCapture(width: width, height: height, device: device)
    }

    /// 名前でカメラを選択してキャプチャデバイスを作成し、**自動的にキャプチャを開始**します。
    ///
    /// 大文字小文字を無視した完全一致を優先し、なければ部分一致で選択します。
    ///
    /// ```swift
    /// capture = createCapture(deviceName: "FaceTime")
    /// ```
    ///
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（デフォルト 1280）。最も近い対応解像度が
    ///     選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（デフォルト 720）。
    ///   - deviceName: 選択するカメラの名前。一致するカメラがない場合は
    ///     `isAvailable == false` のデバイスが返ります。
    /// - Returns: 開始済みのキャプチャデバイス。
    public func createCapture(width: Int = 1280, height: Int = 720, deviceName: String) -> CaptureDevice {
        context.createCapture(width: width, height: height, deviceName: deviceName)
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

    /// 以降のテキスト描画に使うフォントを ``loadFont(_:cache:)`` の結果から設定します。
    ///
    /// - Parameter font: 読み込み済みのフォント。
    public func textFont(_ font: MFont) {
        context.textFont(font)
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

    // MARK: SVG Export

    /// SVG 記録を開始します（Processing の `beginRecord(SVG, path)` 相当）。
    ///
    /// ``endSVGRecord()`` までの 2D 描画呼び出しが、画面へのラスタライズと並行して
    /// 真のベクタ（`<circle>`/`<path>` 等）として記録されます。プロッタ
    /// （AxiDraw 等）や印刷向けの出力に使えます。対応外の機能
    /// （`image()`/`text()` 等）は警告を出力してスキップされます。
    ///
    /// ```swift
    /// func draw() {
    ///     if wantExport { beginSVGRecord("output/sketch.svg") }
    ///     background(255)
    ///     circle(width / 2, height / 2, 200)
    ///     if wantExport { endSVGRecord(); wantExport = false }
    /// }
    /// ```
    ///
    /// - Parameter path: 出力する SVG ファイルパス。
    public func beginSVGRecord(_ path: String) {
        context.beginSVGRecord(path)
    }

    /// SVG 記録を終了し、``beginSVGRecord(_:)`` で指定したパスへ書き出します。
    public func endSVGRecord() {
        context.endSVGRecord()
    }

    /// フレーム連番の画像ファイルとしての記録を開始します。
    ///
    /// ``endFrameRecord()`` を呼ぶまで、毎フレームが `pattern` に従った
    /// 連番ファイル名で `directory` へ書き出されます。
    ///
    /// - Parameters:
    ///   - directory: 出力ディレクトリ（`nil` の場合はデフォルトを使用）。
    ///   - pattern: フレーム番号プレースホルダー付きのファイル名パターン。
    public func beginFrameRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        context.beginFrameRecord(directory: directory, pattern: pattern)
    }

    /// フレーム連番の記録を停止します。
    public func endFrameRecord() {
        context.endFrameRecord()
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
    ///
    /// ``endVideoRecord(completion:)`` の async/await 版です。
    public func endVideoRecordAsync() async {
        await context.endVideoRecordAsync()
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
