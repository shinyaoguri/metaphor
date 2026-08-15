// MARK: - Style (Shape Modes, Color, Fill, Stroke, Blend, Tint)

extension Sketch {

    // MARK: Shape Mode Settings

    /// 矩形の描画モードを設定します。
    ///
    /// - Parameter mode: 矩形の解釈モード。
    ///
    /// ### 実行結果
    ///
    /// 同じ引数の ``rect(_:_:_:_:)`` が、モードによって別の位置・大きさに出ます
    /// （左が既定の ``RectMode/corner``、右が ``RectMode/center``）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rectMode(_:) の実行結果](https://i.gyazo.com/6ac18537fecfcc54f72e033ecca4fa67.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       rectMode(.corner)
    ///       fill(255, 190, 60)
    ///       rect(60, 130, 100, 100)
    ///
    ///       rectMode(.center)
    ///       fill(80, 170, 255)
    ///       rect(340, 180, 100, 100)
    ///       ```
    ///    }
    /// }
    public func rectMode(_ mode: RectMode) {
        context.rectMode(mode)
    }

    /// 楕円の描画モードを設定します。
    ///
    /// - Parameter mode: 楕円の解釈モード。
    public func ellipseMode(_ mode: EllipseMode) {
        context.ellipseMode(mode)
    }

    /// 画像の描画モードを設定します。
    ///
    /// - Parameter mode: 画像の解釈モード。
    public func imageMode(_ mode: ImageMode) {
        context.imageMode(mode)
    }

    // MARK: Color Mode

    /// チャンネルごとの最大値を指定してカラーモードを設定します。
    ///
    /// 既定のカラーモードは RGB の 0〜255（Processing と同じ）です。
    /// 未指定のチャンネルは現在の最大値を維持します。
    ///
    /// - Parameters:
    ///   - space: 使用する色空間。
    ///   - max1: 第1チャンネルの最大値。省略時は現在値を維持。
    ///   - max2: 第2チャンネルの最大値。省略時は現在値を維持。
    ///   - max3: 第3チャンネルの最大値。省略時は現在値を維持。
    ///   - maxA: アルファチャンネルの最大値。省略時は現在値を維持。
    public func colorMode(_ space: ColorSpace, _ max1: Float? = nil, _ max2: Float? = nil, _ max3: Float? = nil, _ maxA: Float? = nil) {
        context.colorMode(space, max1, max2, max3, maxA)
    }

    /// 全チャンネル共通の最大値を指定してカラーモードを設定します。
    ///
    /// - Parameters:
    ///   - space: 使用する色空間。
    ///   - maxAll: 全チャンネルの最大値。
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        context.colorMode(space, maxAll)
    }

    // MARK: Background

    /// 指定した色でキャンバスをクリアします。
    ///
    /// - Parameter color: 背景色。
    public func background(_ color: Color) {
        context.background(color)
    }

    /// グレースケール値でキャンバスをクリアします。
    ///
    /// - Parameter gray: グレースケールの明るさ。既定のカラーモードでは 0 = 黒、255 = 白。
    public func background(_ gray: Float) {
        context.background(gray)
    }

    /// 指定したカラーチャンネル値でキャンバスをクリアします。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    ///   - a: アルファ値（オプション）。
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.background(v1, v2, v3, a)
    }

    // MARK: Style

    /// 塗りつぶし色を設定します。
    ///
    /// - Parameter color: 塗りつぶし色。
    public func fill(_ color: Color) {
        context.fill(color)
    }

    /// チャンネル値で塗りつぶし色を設定します。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    ///   - a: アルファ値（オプション）。
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.fill(v1, v2, v3, a)
    }

    /// グレースケール値で塗りつぶし色を設定します。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func fill(_ gray: Float) {
        context.fill(gray)
    }

    /// アルファ付きグレースケール値で塗りつぶし色を設定します。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func fill(_ gray: Float, _ alpha: Float) {
        context.fill(gray, alpha)
    }

    /// 図形の塗りつぶしを無効にします。
    public func noFill() {
        context.noFill()
    }

    /// ストローク色を設定します。
    ///
    /// - Parameter color: ストローク色。
    public func stroke(_ color: Color) {
        context.stroke(color)
    }

    /// チャンネル値でストローク色を設定します。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    ///   - a: アルファ値（オプション）。
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.stroke(v1, v2, v3, a)
    }

    /// グレースケール値でストローク色を設定します。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func stroke(_ gray: Float) {
        context.stroke(gray)
    }

    /// アルファ付きグレースケール値でストローク色を設定します。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func stroke(_ gray: Float, _ alpha: Float) {
        context.stroke(gray, alpha)
    }

    /// 図形のストロークを無効にします。
    public func noStroke() {
        context.noStroke()
    }

    /// ストロークの太さ（線幅）を設定します。
    ///
    /// - Note: **2D のみ**に作用します（3D のワイヤーフレームには効きません。ADR-0005）。
    ///
    /// - Parameter weight: ストローク幅（ピクセル単位）。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeWeight(_:) の実行結果](https://i.gyazo.com/d8e6cd010c5b5629ebfd57cf15e400ba.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255)
    ///       var y: Float = 70
    ///       for weight in [1, 4, 12, 28] {
    ///           strokeWeight(Float(weight))
    ///           line(80, y, 400, y)
    ///           y += 70
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeWeight(_ weight: Float) {
        context.strokeWeight(weight)
    }

    /// ストロークの端点スタイルを設定します。
    ///
    /// - Parameter cap: 線の端点スタイル。
    public func strokeCap(_ cap: StrokeCap) {
        context.strokeCap(cap)
    }

    /// ストロークの接続スタイルを設定します。
    ///
    /// - Parameter join: 線の接続スタイル。
    public func strokeJoin(_ join: StrokeJoin) {
        context.strokeJoin(join)
    }

    /// 以降の描画操作のブレンドモードを設定します。
    ///
    /// - Note: **2D のみ**に作用します（3D は不透明/加算のマテリアル設定に従います。
    ///   ADR-0005）。
    ///
    /// - Parameter mode: 適用するブレンドモード。
    ///
    /// ### 実行結果
    ///
    /// ``BlendMode/additive`` は重なりが明るくなり、``BlendMode/alpha``（既定）は
    /// 後から描いたほうが上に乗ります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![blendMode(_:) の実行結果](https://i.gyazo.com/c073f497a82f5354038960f521ec3029.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       blendMode(.additive)
    ///       fill(255, 60, 60)
    ///       circle(190, 150, 150)
    ///       fill(60, 255, 60)
    ///       circle(260, 150, 150)
    ///       fill(60, 60, 255)
    ///       circle(225, 220, 150)
    ///       ```
    ///    }
    /// }
    public func blendMode(_ mode: BlendMode) {
        context.blendMode(mode)
    }

    // MARK: Tint

    /// 画像のティント色を設定します。
    ///
    /// - Parameter color: ティント色。
    public func tint(_ color: Color) {
        context.tint(color)
    }

    /// チャンネル値で画像のティント色を設定します。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    ///   - a: アルファ値（オプション）。
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.tint(v1, v2, v3, a)
    }

    /// グレースケール値で画像のティントを設定します。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func tint(_ gray: Float) {
        context.tint(gray)
    }

    /// アルファ付きグレースケール値で画像のティントを設定します。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func tint(_ gray: Float, _ alpha: Float) {
        context.tint(gray, alpha)
    }

    /// 画像のティントを解除します。
    public func noTint() {
        context.noTint()
    }
}
