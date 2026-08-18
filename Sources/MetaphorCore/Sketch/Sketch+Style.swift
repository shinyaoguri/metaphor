// MARK: - Style (Shape Modes, Color, Fill, Stroke, Blend, Tint)

extension Sketch {

    // MARK: Shape Mode Settings

    /// 矩形の描画モードを設定します。
    ///
    /// - Note: **2D のみ**に作用します（``rect(_:_:_:_:)`` 用で、3D のプリミティブの
    ///   位置の解釈には効きません。ADR-0005）。
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
    /// - Note: **2D のみ**に作用します（``ellipse(_:_:_:_:)`` 用で、3D のプリミティブの
    ///   位置の解釈には効きません。ADR-0005）。
    ///
    /// - Parameter mode: 楕円の解釈モード。
    ///
    /// ### 実行結果
    ///
    /// 同じ引数の ``ellipse(_:_:_:_:)`` が、モードによって別の位置に出ます
    /// （左が既定の ``EllipseMode/center``、右が ``EllipseMode/corner``）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ellipseMode(_:) の実行結果](https://i.gyazo.com/4873852670151d89625389351ee618d0.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///
    ///       ellipseMode(.center)
    ///       fill(255, 190, 60)
    ///       ellipse(140, 180, 140, 100)
    ///
    ///       ellipseMode(.corner)
    ///       fill(80, 170, 255)
    ///       ellipse(280, 130, 140, 100)
    ///       ```
    ///    }
    /// }
    public func ellipseMode(_ mode: EllipseMode) {
        context.ellipseMode(mode)
    }

    /// 画像の描画モードを設定します。
    ///
    /// - Note: **2D のみ**に作用します（`image()` 用で、3D の ``texture(_:)`` には
    ///   効きません。ADR-0005）。
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
    /// - Note: **2D と 3D の両方**に作用します（``fill(_:)-(Color)`` / ``stroke(_:)-(Color)`` の
    ///   チャンネル解釈が両キャンバスで揃います。ADR-0005）。
    ///
    /// - Parameters:
    ///   - space: 使用する色空間。
    ///   - max1: 第1チャンネルの最大値。省略時は現在値を維持。
    ///   - max2: 第2チャンネルの最大値。省略時は現在値を維持。
    ///   - max3: 第3チャンネルの最大値。省略時は現在値を維持。
    ///   - maxA: アルファチャンネルの最大値。省略時は現在値を維持。
    ///
    /// ### 実行結果
    ///
    /// ``ColorSpace/hsb`` にすると、第1チャンネルが色相になります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![colorMode(_:_:_:_:_:) の実行結果](https://i.gyazo.com/9f0d6c7c8fee971710865b73239fa811.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       colorMode(.hsb, 360, 100, 100, 100)
    ///       noStroke()
    ///       for i in 0..<12 {
    ///           fill(Float(i) * 30, 80, 100)
    ///           rect(Float(i) * 40, 120, 40, 120)
    ///       }
    ///       ```
    ///    }
    /// }
    public func colorMode(_ space: ColorSpace, _ max1: Float? = nil, _ max2: Float? = nil, _ max3: Float? = nil, _ maxA: Float? = nil) {
        context.colorMode(space, max1, max2, max3, maxA)
    }

    /// 全チャンネル共通の最大値を指定してカラーモードを設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（``fill(_:)-(Color)`` / ``stroke(_:)-(Color)`` の
    ///   チャンネル解釈が両キャンバスで揃います。ADR-0005）。
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
    /// **クリアは合成ではなく置き換え**です。`blendMode()` は効かず、α < 1 の背景色は
    /// 下地と混ざらずにそのまま入ります（`background(0, 0, 0, 0)` はキャンバスを透明に
    /// 戻します）。前フレームを薄く残したいときは、背景色の `rect()` を画面いっぱいに
    /// 描いてください（ADR-0012 / #829）。
    ///
    /// - Note: **2D と 3D の両方**に作用します。オフスクリーンのキャンバスは 2D と 3D で
    ///   共有されているため、既に描いた 3D も一緒に消えます（ADR-0005）。
    ///
    /// - Parameter color: 背景色。
    public func background(_ color: Color) {
        context.background(color)
    }

    /// グレースケール値でキャンバスをクリアします。
    ///
    /// - Note: **2D と 3D の両方**に作用します。オフスクリーンのキャンバスは 2D と 3D で
    ///   共有されているため、既に描いた 3D も一緒に消えます（ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。既定のカラーモードでは 0 = 黒、255 = 白。
    public func background(_ gray: Float) {
        context.background(gray)
    }

    /// 指定したカラーチャンネル値でキャンバスをクリアします。
    ///
    /// - Note: **2D と 3D の両方**に作用します。オフスクリーンのキャンバスは 2D と 3D で
    ///   共有されているため、既に描いた 3D も一緒に消えます（ADR-0005）。
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
    /// - Note: **2D と 3D の両方**に作用します。3D ではプリミティブやメッシュの色になり、
    ///   ``texture(_:)`` を貼っているときはテクスチャの色に乗算されます（ADR-0005）。
    ///
    /// - Parameter color: 塗りつぶし色。
    public func fill(_ color: Color) {
        context.fill(color)
    }

    /// チャンネル値で塗りつぶし色を設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（3D ではプリミティブやメッシュの色に
    ///   なります。ADR-0005）。
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
    /// - Note: **2D と 3D の両方**に作用します（3D ではプリミティブやメッシュの色に
    ///   なります。ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func fill(_ gray: Float) {
        context.fill(gray)
    }

    /// アルファ付きグレースケール値で塗りつぶし色を設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（3D ではプリミティブやメッシュの色に
    ///   なります。ADR-0005）。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func fill(_ gray: Float, _ alpha: Float) {
        context.fill(gray, alpha)
    }

    /// 図形の塗りつぶしを無効にします。
    ///
    /// - Note: **2D と 3D の両方**に作用します。3D では面が描かれなくなり、
    ///   ``noStroke()`` も併せて呼ぶとそのシェイプは何も描かれません（ADR-0005）。
    ///
    /// ### 実行結果
    ///
    /// 塗りだけが消え、ストロークは残ります（右が ``noFill()`` を呼んだあと）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![noFill() の実行結果](https://i.gyazo.com/01df4c758c2b0ef1adef4252a47eef79.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(6)
    ///       fill(80, 170, 255)
    ///       circle(150, 180, 150)
    ///       noFill()
    ///       circle(330, 180, 150)
    ///       ```
    ///    }
    /// }
    public func noFill() {
        context.noFill()
    }

    /// ストローク色を設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します。ただし太さを決める ``strokeWeight(_:)``
    ///   は **2D のみ**なので、3D の線の太さは変えられません（ADR-0005）。
    ///
    /// - Parameter color: ストローク色。
    public func stroke(_ color: Color) {
        context.stroke(color)
    }

    /// チャンネル値でストローク色を設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（太さを決める ``strokeWeight(_:)`` は
    ///   2D のみ。ADR-0005）。
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
    /// - Note: **2D と 3D の両方**に作用します（太さを決める ``strokeWeight(_:)`` は
    ///   2D のみ。ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func stroke(_ gray: Float) {
        context.stroke(gray)
    }

    /// アルファ付きグレースケール値でストローク色を設定します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（太さを決める ``strokeWeight(_:)`` は
    ///   2D のみ。ADR-0005）。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func stroke(_ gray: Float, _ alpha: Float) {
        context.stroke(gray, alpha)
    }

    /// 図形のストロークを無効にします。
    ///
    /// - Note: **2D と 3D の両方**に作用します。3D の既定は元からストローク無しなので、
    ///   ``stroke(_:)-(Color)`` を呼んでいなければ見た目は変わりません（ADR-0005）。
    ///
    /// ### 実行結果
    ///
    /// 輪郭だけが消え、塗りは残ります（右が ``noStroke()`` を呼んだあと）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![noStroke() の実行結果](https://i.gyazo.com/6196c1479b479d50c9d06fa4943ad56d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255)
    ///       strokeWeight(8)
    ///       fill(255, 190, 60)
    ///       circle(150, 180, 150)
    ///       noStroke()
    ///       circle(330, 180, 150)
    ///       ```
    ///    }
    /// }
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
    /// - Note: **2D のみ**に作用します（``strokeWeight(_:)`` と同じく、3D の線には
    ///   効きません。ADR-0005）。
    ///
    /// - Parameter cap: 線の端点スタイル。
    ///
    /// ### 実行結果
    ///
    /// 上から ``StrokeCap/butt``（既定）/ ``StrokeCap/round`` /
    /// ``StrokeCap/square``。太い線ほど差が出ます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeCap(_:) の実行結果](https://i.gyazo.com/adb3a1d176e5578166f0633159e709a3.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       let caps: [StrokeCap] = [
    ///           .butt, .round, .square
    ///       ]
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(26)
    ///       var y: Float = 90
    ///       for cap in caps {
    ///           strokeCap(cap)
    ///           line(140, y, 340, y)
    ///           y += 90
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeCap(_ cap: StrokeCap) {
        context.strokeCap(cap)
    }

    /// ストロークの接続スタイルを設定します。
    ///
    /// - Note: **2D のみ**に作用します（``strokeWeight(_:)`` と同じく、3D の線には
    ///   効きません。ADR-0005）。
    ///
    /// - Parameter join: 線の接続スタイル。
    ///
    /// ### 実行結果
    ///
    /// 左から ``StrokeJoin/miter``（既定。角を尖らせる）/ ``StrokeJoin/round``
    /// （半径 `strokeWeight / 2` の弧で丸める）/ ``StrokeJoin/bevel``（平らに落とす）。
    /// 太い線ほど差が出ます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![strokeJoin(_:) の実行結果](https://i.gyazo.com/7d327109e9183273cabce9fb05601bf5.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       let joins: [StrokeJoin] = [
    ///           .miter, .round, .bevel
    ///       ]
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(22)
    ///       var x: Float = 70
    ///       for join in joins {
    ///           strokeJoin(join)
    ///           beginShape()
    ///           vertex(x, 240)
    ///           vertex(x + 45, 120)
    ///           vertex(x + 90, 240)
    ///           endShape()
    ///           x += 140
    ///       }
    ///       ```
    ///    }
    /// }
    public func strokeJoin(_ join: StrokeJoin) {
        context.strokeJoin(join)
    }

    /// 以降の描画操作のブレンドモードを設定します。
    ///
    /// `fill` / `stroke` のアルファは、どのモードでも**混ぜ方をどれだけ効かせるか**を表します
    /// （ADR-0012）。`α = 0` はどのモードでも何も起こらず、`α = 0.5` は下地とそのモードの
    /// 合成結果のちょうど中間になります。結果のアルファはモードによらず
    /// `src.a + dst.a · (1 − src.a)` で、``blendMode(_:)`` が塗った領域の不透明度を
    /// 削ることはありません。
    ///
    /// - Note: **2D のみ**に作用します（3D は不透明/加算のマテリアル設定に従います。
    ///   ADR-0005）。
    ///
    /// - Note: ``BlendMode/multiply`` / ``BlendMode/screen`` / ``BlendMode/subtract`` /
    ///   ``BlendMode/lightest`` / ``BlendMode/darkest`` / ``BlendMode/difference`` /
    ///   ``BlendMode/exclusion`` は描き込み先の色を読む専用フラグメントで実装されているため、
    ///   **カスタム 2D シェーダとは併用できません**（適用中は ``BlendMode/alpha`` へ落ち、
    ///   コンソールへ 1 度だけ警告が出ます）。
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
    /// - Note: **2D のみ**に作用します。掛かるのは `image()` で描く画像だけで、
    ///   3D の ``texture(_:)`` には効きません——3D のテクスチャは ``fill(_:)-(Color)`` の色を
    ///   乗算して着色するため、ティント専用のスロットがそもそもありません（ADR-0005）。
    ///   テクスチャ付きの 3D に色を掛けたいときは ``fill(_:)-(Color)`` を使ってください。
    ///
    /// - Parameter color: ティント色。
    public func tint(_ color: Color) {
        context.tint(color)
    }

    /// チャンネル値で画像のティント色を設定します。
    ///
    /// - Note: **2D のみ**に作用します（3D のテクスチャは ``fill(_:)-(Color)`` の色で着色します。
    ///   ADR-0005）。
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
    /// - Note: **2D のみ**に作用します（3D のテクスチャは ``fill(_:)-(Color)`` の色で着色します。
    ///   ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func tint(_ gray: Float) {
        context.tint(gray)
    }

    /// アルファ付きグレースケール値で画像のティントを設定します。
    ///
    /// - Note: **2D のみ**に作用します（3D のテクスチャは ``fill(_:)-(Color)`` の色で着色します。
    ///   ADR-0005）。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明るさ。
    ///   - alpha: アルファ（不透明度）値。
    public func tint(_ gray: Float, _ alpha: Float) {
        context.tint(gray, alpha)
    }

    /// 画像のティントを解除します。
    ///
    /// - Note: **2D のみ**に作用します（``tint(_:)-(Color)`` と対。ADR-0005）。
    public func noTint() {
        context.noTint()
    }
}
