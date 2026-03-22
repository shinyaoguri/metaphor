extension SketchContext {

    // MARK: - Shape Mode Settings

    /// 矩形の座標解釈モードを設定します。
    /// - Parameter mode: 矩形の描画モード。
    public func rectMode(_ mode: RectMode) {
        canvas.rectMode(mode)
    }

    /// 楕円の座標解釈モードを設定します。
    /// - Parameter mode: 楕円の描画モード。
    public func ellipseMode(_ mode: EllipseMode) {
        canvas.ellipseMode(mode)
    }

    /// 画像の座標解釈モードを設定します。
    /// - Parameter mode: 画像の描画モード。
    public func imageMode(_ mode: ImageMode) {
        canvas.imageMode(mode)
    }

    // MARK: - Drawing Style

    /// 現在の共有描画スタイルを返します。
    public var drawingStyle: DrawingStyle {
        get {
            DrawingStyle(
                fillColor: canvas.fillColor,
                strokeColor: canvas.strokeColor,
                hasFill: canvas.hasFill,
                hasStroke: canvas.hasStroke,
                colorModeConfig: canvas.colorModeConfig
            )
        }
        set {
            canvas.syncStyle(newValue)
            canvas3D.syncStyle(newValue)
        }
    }

    // MARK: - Color Mode

    /// 2D・3D 両方のキャンバスに色空間とチャンネル最大値を設定します。
    /// - Parameters:
    ///   - space: 使用する色空間。
    ///   - max1: 第1チャンネルの最大値。
    ///   - max2: 第2チャンネルの最大値。
    ///   - max3: 第3チャンネルの最大値。
    ///   - maxA: アルファチャンネルの最大値。
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        canvas.colorMode(space, max1, max2, max3, maxA)
        canvas3D.colorMode(space, max1, max2, max3, maxA)
    }

    /// 2D・3D 両方のキャンバスに色空間と全チャンネル共通の最大値を設定します。
    /// - Parameters:
    ///   - space: 使用する色空間。
    ///   - maxAll: 全チャンネル共通の最大値。
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas.colorMode(space, maxAll)
        canvas3D.colorMode(space, maxAll)
    }

    // MARK: - Background

    /// 指定した色で背景を塗りつぶします。
    /// - Parameter color: 背景色。
    public func background(_ color: Color) {
        canvas.background(color)
    }

    /// グレースケール値で背景を塗りつぶします。
    /// - Parameter gray: グレースケールの強度。
    public func background(_ gray: Float) {
        canvas.background(gray)
    }

    /// 現在のカラーモードに従って解釈されるカラー成分で背景を塗りつぶします。
    /// - Parameters:
    ///   - v1: 第1カラー成分。
    ///   - v2: 第2カラー成分。
    ///   - v3: 第3カラー成分。
    ///   - a: アルファ値（オプション）。
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.background(v1, v2, v3, a)
    }

    // MARK: - Style (2D + 3D shared via CanvasStyle protocol)

    /// 共有スタイル操作用に両方のキャンバスを配列として保持。
    private var canvases: [any CanvasStyle] { [canvas, canvas3D] }

    /// 2D・3D 両方のキャンバスに塗りつぶし色を設定します。
    /// - Parameter color: 塗りつぶし色。
    public func fill(_ color: Color) {
        canvases.forEach { $0.fill(color) }
    }

    /// 現在のカラーモードに従って解釈される塗りつぶし色を 2D・3D 両方のキャンバスに設定します。
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvases.forEach { $0.fill(v1, v2, v3, a) }
    }

    /// グレースケール値で 2D・3D 両方のキャンバスに塗りつぶし色を設定します。
    public func fill(_ gray: Float) {
        canvases.forEach { $0.fill(gray) }
    }

    /// アルファ付きグレースケール値で 2D・3D 両方のキャンバスに塗りつぶし色を設定します。
    public func fill(_ gray: Float, _ alpha: Float) {
        canvases.forEach { $0.fill(gray, alpha) }
    }

    /// 2D・3D 両方のキャンバスの塗りつぶしを無効にします。
    public func noFill() {
        canvases.forEach { $0.noFill() }
    }

    /// 2D・3D 両方のキャンバスにストローク色を設定します。
    public func stroke(_ color: Color) {
        canvases.forEach { $0.stroke(color) }
    }

    /// 現在のカラーモードに従って解釈されるストローク色を 2D・3D 両方のキャンバスに設定します。
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvases.forEach { $0.stroke(v1, v2, v3, a) }
    }

    /// グレースケール値で 2D・3D 両方のキャンバスにストローク色を設定します。
    public func stroke(_ gray: Float) {
        canvases.forEach { $0.stroke(gray) }
    }

    /// アルファ付きグレースケール値で 2D・3D 両方のキャンバスにストローク色を設定します。
    public func stroke(_ gray: Float, _ alpha: Float) {
        canvases.forEach { $0.stroke(gray, alpha) }
    }

    /// 2D・3D 両方のキャンバスのストロークを無効にします。
    public func noStroke() {
        canvases.forEach { $0.noStroke() }
    }

    /// ストロークの太さを設定します（2D のみ）。
    /// - Parameter weight: 線の太さ（ピクセル単位）。
    public func strokeWeight(_ weight: Float) {
        canvas.strokeWeight(weight)
    }

    /// ストロークの端点スタイルを設定します。
    /// - Parameter cap: ストロークの端点スタイル。
    public func strokeCap(_ cap: StrokeCap) {
        canvas.strokeCap(cap)
    }

    /// ストロークの接続スタイルを設定します。
    /// - Parameter join: ストロークの角の接続スタイル。
    public func strokeJoin(_ join: StrokeJoin) {
        canvas.strokeJoin(join)
    }

    /// レンダリングのブレンドモードを設定します。
    /// - Parameter mode: 適用するブレンドモード。
    public func blendMode(_ mode: BlendMode) {
        canvas.blendMode(mode)
    }

    // MARK: - Tint

    /// 画像のティント色を設定します。
    /// - Parameter color: ティント色。
    public func tint(_ color: Color) {
        canvas.tint(color)
    }

    /// 現在のカラーモードに従って解釈されるティント色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラー成分。
    ///   - v2: 第2カラー成分。
    ///   - v3: 第3カラー成分。
    ///   - a: アルファ値（オプション）。
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.tint(v1, v2, v3, a)
    }

    /// グレースケール値でティント色を設定します。
    /// - Parameter gray: グレースケールの強度。
    public func tint(_ gray: Float) {
        canvas.tint(gray)
    }

    /// アルファ付きグレースケール値でティント色を設定します。
    /// - Parameters:
    ///   - gray: グレースケールの強度。
    ///   - alpha: アルファ値。
    public func tint(_ gray: Float, _ alpha: Float) {
        canvas.tint(gray, alpha)
    }

    /// 画像のティントを無効にします。
    public func noTint() {
        canvas.noTint()
    }
}
