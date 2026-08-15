import AppKit
import Metal

extension SketchContext {

    // MARK: - Image

    /// 指定したファイルパスから画像を読み込みます。
    ///
    /// 既定でパスキーのキャッシュが効き、同じパスの再読込は同一の ``MImage``
    /// インスタンスを返します（`draw()` 内で呼んでも再デコードされません）。
    ///
    /// - Parameters:
    ///   - path: 画像のファイルパス。
    ///   - cache: キャッシュを使うか（既定 true。false で独立したコピーを読み込み）。
    /// - Returns: 読み込まれた画像。
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   指定されたパスからテクスチャを読み込めない場合（不在・非対応フォーマット・I/O エラー）。
    public func loadImage(_ path: String, cache: Bool = true) throws -> MImage {
        if cache, let cached = assetCache.image(forPath: path) {
            return cached
        }
        let image = try MImage(path: path, device: renderer.device)
        if cache {
            assetCache.store(image, forPath: path)
        }
        return image
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
        if cache, let cached = assetCache.image(forPath: path) {
            return cached
        }
        let image = try await resourceLoader.loadImageAsync(path: path)
        if cache {
            assetCache.store(image, forPath: path)
        }
        return image
    }

    // MARK: - Text Outline

    /// テキストのグリフアウトラインを、輪郭ごとの閉じたポリラインとして返します。
    ///
    /// 現在の ``textSize(_:)`` / ``textFont(_:)-(String)`` / ``textAlign(_:_:)`` を
    /// `text()` と同じように解釈します。
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
        canvas.textToContours(string, x, y, sampleFactor: sampleFactor)
    }

    /// テキストのグリフアウトライン上の点を 1 本の配列で返します（p5 の `textToPoints` 相当）。
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
        canvas.textToPoints(string, x, y, sampleFactor: sampleFactor)
    }

    /// テキストのアウトラインを、穴つきで描けるリテインドシェイプへ変換します。
    ///
    /// 返るのは外周ごとの子を持つ ``ShapeKind/group``。`o` の内側のような穴は
    /// コンターとして子に載るため、``shape(_:_:_:)`` でそのまま塗り分けられます。
    ///
    /// ```swift
    /// let logo = textToShape("metaphor", 40, 200)
    /// logo.setFill(.white)
    /// shape(logo, 0, 0)
    /// ```
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
        let group = createShape(.group)
        let contours = canvas.textToContours(string, x, y, sampleFactor: sampleFactor)
        for nested in ContourNesting.group(contours) {
            let child = createShape()
            child.beginShape()
            for point in nested.outer { child.vertex(point.x, point.y) }
            for hole in nested.holes {
                child.beginContour()
                for point in hole { child.vertex(point.x, point.y) }
                child.endContour()
            }
            child.endShape(.close)
            group.addChild(child)
        }
        return group
    }

    // MARK: - Font

    /// 指定したファイルパスからフォントを読み込みます。
    ///
    /// フォントは現在のプロセスにだけ登録されます（システムのフォント設定は変更しません）。
    /// 返された ``MFont`` を ``textFont(_:)-(MFont)`` へ渡すと、以降のテキスト描画・計測が
    /// そのフォントで行われます。
    ///
    /// 既定でパスキーのキャッシュが効き、同じパスの再読込は同一の ``MFont`` を返します
    /// （`draw()` 内で呼んでも再登録されません）。
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
        if cache, let cached = assetCache.font(forPath: path) {
            return cached
        }
        let font = try FontRegistry.load(path: path)
        if cache {
            assetCache.store(font, forPath: path)
        }
        return font
    }

    // MARK: - SVG Export

    /// SVG 記録を開始します。
    ///
    /// 以降の 2D 描画呼び出しは画面へのラスタライズと並行して SVG にも記録され、
    /// ``endSVGRecord()`` でファイルへ書き出されます。対応外の機能（`image()`/`text()`/
    /// グラデーション等）は警告を出力してスキップされます（機能ごとに 1 回）。
    ///
    /// - Parameter path: 出力する SVG ファイルパス。
    public func beginSVGRecord(_ path: String) {
        guard canvas.svgRecorder == nil else {
            metaphorWarning("beginSVGRecord: SVG recording is already active")
            return
        }
        canvas.svgRecorder = SVGRecorder(
            width: canvas.width, height: canvas.height, outputPath: path)
    }

    /// SVG 記録を終了し、``beginSVGRecord(_:)`` で指定したパスへ書き出します。
    ///
    /// 親ディレクトリがなければ作成します。出力は決定論的（同じ描画呼び出し列
    /// からは常に同じバイト列）で、ゴールデンファイル比較でテストできます。
    public func endSVGRecord() {
        guard let recorder = canvas.svgRecorder else {
            metaphorWarning("endSVGRecord: no active SVG recording (call beginSVGRecord first)")
            return
        }
        canvas.svgRecorder = nil
        do {
            try DataIO.writeData(Data(recorder.svgString().utf8), toPath: recorder.outputPath)
        } catch {
            metaphorWarning("endSVGRecord: failed to write SVG: \(error.localizedDescription)")
        }
    }

    /// キャンバスの矩形領域を別の矩形領域へコピーします（Processing の `copy()` 互換）。
    ///
    /// コピー元はオフスクリーンレンダーターゲットの現在の内容（前フレームまでの
    /// 描画結果）。コピー先への描画は現在のフレームの描画コマンドとして実行され、
    /// `imageMode` / `tint` の影響を受けない絶対座標で描かれます。
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
        guard sw > 0, sh > 0, dw > 0, dh > 0 else {
            metaphorWarning("copy: source/destination size must be positive")
            return
        }
        let src = renderer.textureManager.colorTexture
        // ソース矩形を整数化してテクスチャ範囲へクランプ
        let x0 = max(0, Int(sx))
        let y0 = max(0, Int(sy))
        let x1 = min(src.width, Int(sx + sw))
        let y1 = min(src.height, Int(sy + sh))
        guard x1 > x0, y1 > y0 else {
            metaphorWarning("copy: source region (\(sx),\(sy),\(sw),\(sh)) is outside the canvas")
            return
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: src.pixelFormat, width: x1 - x0, height: y1 - y0, mipmapped: false)
        desc.storageMode = .private
        desc.usage = [.shaderRead]
        guard let regionTexture = renderer.device.makeTexture(descriptor: desc),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            metaphorWarning("copy: failed to allocate copy resources")
            return
        }
        blit.copy(
            from: src, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: x0, y: y0, z: 0),
            sourceSize: MTLSize(width: x1 - x0, height: y1 - y0, depth: 1),
            to: regionTexture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        // 同一キューのため、フレーム末の描画コマンド実行前に blit の完了が保証される
        commandBuffer.commit()

        let img = MImage(texture: regionTexture)
        let savedMode = canvas.currentImageMode
        let savedTint = canvas.hasTint
        canvas.imageMode(.corner)
        canvas.hasTint = false
        canvas.image(img, dx, dy, dw, dh)
        canvas.imageMode(savedMode)
        canvas.hasTint = savedTint
    }

    /// ピクセル操作用の空の画像を作成します。
    /// - Parameters:
    ///   - width: 画像の幅（ピクセル単位）。
    ///   - height: 画像の高さ（ピクセル単位）。
    /// - Returns: 新しい空白画像。失敗時は nil。
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        guard width > 0, height > 0 else {
            metaphorWarning("createImage: dimensions must be positive (got \(width)x\(height))")
            return nil
        }
        return MImage.createImage(width, height, device: renderer.device)
    }

    /// 画像に GPU 画像フィルターを適用します。
    ///
    /// レンダラ経由のため CPU 版 ``MImage/filter(_:)`` より高速です。レンダラを
    /// 必要としない単体画像の処理には CPU 版を使ってください。
    ///
    /// - Parameters:
    ///   - image: 対象の画像。
    ///   - type: 適用するフィルタータイプ。
    public func filter(_ image: MImage, _ type: FilterType) {
        renderer.imageFilterGPU.apply(type, to: image)
    }

    /// オフスクリーン 2D 描画バッファを作成します。
    ///
    /// 1 枚を同一フレーム内で描き換えて何度でも貼れます。`image()` で描かれるのは
    /// **貼った時点の内容**です（描き換えるたびに描き先が別のテクスチャへ回るため、
    /// 使い回した回数ぶん内部テクスチャが増えます。#745）。
    ///
    /// ```swift
    /// pg.beginDraw(); pg.background(60, 120, 240); pg.endDraw()
    /// image(pg, 100, 100)   // 青
    /// pg.beginDraw(); pg.background(60, 220, 120); pg.endDraw()
    /// image(pg, 300, 100)   // 緑（100,100 は青のまま）
    /// ```
    ///
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい Graphics インスタンス。失敗時は nil。
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        let graphics = try? Graphics(
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
        // オフスクリーンでもカスタム 2D シェーダの time / mouse が効くようにする（#647）。
        graphics?.wireShaderInputs { [weak self] in
            self?.shaderInputs() ?? Canvas2DShaderInputs(
                time: 0, mouse: SIMD2<Float>(0, 0), frameCount: 0)
        }
        return graphics
    }

    /// オフスクリーン 3D 描画バッファを作成します。
    /// - Parameters:
    ///   - w: バッファの幅（ピクセル単位）。
    ///   - h: バッファの高さ（ピクセル単位）。
    /// - Returns: 新しい Graphics3D インスタンス。失敗時は nil。
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        let graphics = try? Graphics3D(
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
        // 描画先テクスチャを使い回してよい時期の判定に使う（#745）
        graphics?.wireFrameCount { [weak self] in
            UInt32(truncatingIfNeeded: self?.frameCount ?? 0)
        }
        return graphics
    }

    // MARK: - Camera Capture

    /// 接続中のカメラを列挙します。
    /// - Returns: 接続中のカメラの一覧（接続がなければ空配列）。
    public func listCaptureDevices() -> [CaptureDeviceInfo] {
        CaptureDevice.list()
    }

    /// カメラキャプチャデバイスを作成し自動的にキャプチャを開始します。
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（ピクセル単位、デフォルト 1280）。最も近い
    ///     対応解像度が選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（ピクセル単位、デフォルト 720）。
    ///   - position: カメラの位置。`nil`（デフォルト）の場合は
    ///     ユーザー/システムの優先カメラを使用します。
    /// - Returns: 開始済みの `CaptureDevice` インスタンス。
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition? = nil) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, position: position)
        capture.start()
        return capture
    }

    /// 指定したカメラでキャプチャデバイスを作成し自動的にキャプチャを開始します。
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（ピクセル単位、デフォルト 1280）。最も近い
    ///     対応解像度が選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（ピクセル単位、デフォルト 720）。
    ///   - device: ``listCaptureDevices()`` で取得したデバイス情報。
    /// - Returns: 開始済みの `CaptureDevice` インスタンス。
    public func createCapture(width: Int = 1280, height: Int = 720, device info: CaptureDeviceInfo) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, captureDevice: info)
        capture.start()
        return capture
    }

    /// 名前でカメラを選択してキャプチャデバイスを作成し自動的にキャプチャを開始します。
    /// - Parameters:
    ///   - width: 要求するキャプチャ幅（ピクセル単位、デフォルト 1280）。最も近い
    ///     対応解像度が選択され、実際の値は ``CaptureDevice/actualWidth`` で確認できます。
    ///   - height: 要求するキャプチャ高さ（ピクセル単位、デフォルト 720）。
    ///   - deviceName: 選択するカメラの名前（大文字小文字を無視した完全一致優先、次に部分一致）。
    /// - Returns: 開始済みの `CaptureDevice` インスタンス。
    public func createCapture(width: Int = 1280, height: Int = 720, deviceName: String) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, deviceName: deviceName)
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
    ///
    /// 描かれるのは**呼んだ時点の内容**です。同じバッファを描き換えて同一フレーム内で
    /// 何度でも貼れます（#745）。
    ///
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
    ///
    /// 描かれるのは**呼んだ時点の内容**です。同じバッファを描き換えて同一フレーム内で
    /// 何度でも貼れます（#745）。
    ///
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
    ///
    /// Processing と同じく行間（``textLeading(_:)``）は既定値へ戻ります。
    ///
    /// - Parameter size: フォントサイズ（ポイント単位）。
    public func textSize(_ size: Float) {
        canvas.textSize(size)
    }

    /// テキストレンダリングのフォントファミリーを設定します。
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) {
        canvas.textFont(family)
    }

    /// テキストレンダリングに使うフォントを ``loadFont(_:cache:)`` の結果から設定します。
    /// - Parameter font: 読み込み済みのフォント。
    public func textFont(_ font: MFont) {
        canvas.textFont(font)
    }

    /// テキストの配置を設定します。
    /// - Parameters:
    ///   - horizontal: 水平方向の配置。
    ///   - vertical: 垂直方向の配置（デフォルト `.baseline`）。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// 複数行テキストの行間（行の高さ）を設定します。
    ///
    /// ``textSize(_:)`` / ``textFont(_:)`` を呼ぶと既定値へ戻ります。
    ///
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
    public func beginFrameRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
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
    public func endFrameRecord() {
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
        do {
            try renderer.videoExporter.beginRecord(
                path: actualPath,
                width: renderer.textureManager.width,
                height: renderer.textureManager.height,
                config: config
            )
        } catch {
            // 無効なパスやエンコーダー開始失敗を黙って握り潰さず通知する。
            metaphorWarning("beginVideoRecord failed for \(actualPath): \(error)")
        }
    }

    /// 動画録画を終了します。
    /// - Parameter completion: 書き込み完了時に呼ばれるコールバック。
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        renderer.videoExporter.endRecord(completion: completion)
    }

    /// 動画録画を非同期で終了します。
    ///
    /// ``endVideoRecord(completion:)`` の async/await 版です。
    public func endVideoRecordAsync() async {
        await renderer.videoExporter.endRecordAsync()
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
    ///
    /// 返される画像は `loadPixels()` / `get()` による CPU 読み取りにも使えます
    /// （リードバックは前フレームのコピーを行った描画キューに載るため、
    /// そのフレーム冒頭のコピー完了後の内容が読めます）。
    /// - Returns: 前フレームの `MImage`。または nil。
    public func previousFrame() -> MImage? {
        guard let tex = renderer.previousFrameTexture else { return nil }
        let image = MImage(texture: tex)
        // 前フレームのコピー（capturePreviousFrame）はフレームのコマンドバッファ、
        // すなわち renderer.commandQueue に載る。リードバックを同じキューに載せ、
        // commit 順序で「コピー → loadPixels」を正しく順序付ける
        image.preferredReadbackQueue = renderer.commandQueue
        return image
    }
}
