// MARK: - 2D Transform & Shapes

extension Sketch {

    // MARK: 2D Transform Stack

    /// 現在の変換とスタイル状態をスタックに保存します。
    ///
    /// - Note: **2D と 3D の両方**に作用します。``pushMatrix()`` との違いは作用先ではなく
    ///   「スタイルを含むかどうか」で、こちらは変換 + スタイル、``pushMatrix()`` は変換のみです。
    ///
    /// ### 実行結果
    ///
    /// ``pop()`` を呼ぶと、あいだで変えた変換もスタイルも巻き戻ります
    /// （青い矩形は ``translate(_:_:)`` の影響を受けません）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![push() の実行結果](https://i.gyazo.com/ed6c97031c145c2561123ddf7fa4d8ad.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       push()
    ///       translate(120, 100)
    ///       fill(255, 190, 60)
    ///       rect(-60, -50, 120, 100)
    ///       pop()
    ///       fill(80, 170, 255)
    ///       rect(260, 210, 120, 100)
    ///       ```
    ///    }
    /// }
    public func push() {
        context.push()
    }

    /// 最後に保存された変換とスタイル状態をスタックから復元します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（``push()`` と対）。
    public func pop() {
        context.pop()
    }

    /// 現在のスタイル状態（fill、stroke など）をスタックに保存します。
    ///
    /// - Note: **2D と 3D の両方**に作用します。``push()`` との違いは変換を含まないことで、
    ///   こちらはスタイルのみを保存します（ADR-0005 Amendment 2026-08-02）。
    public func pushStyle() {
        context.pushStyle()
    }

    /// 最後に保存されたスタイル状態をスタックから復元します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（``pushStyle()`` と対）。
    public func popStyle() {
        context.popStyle()
    }

    /// 現在の変換に平行移動を適用します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（3D は z = 0 の平行移動。
    ///   Processing P3D 互換。ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameters:
    ///   - x: 水平方向の移動量。
    ///   - y: 垂直方向の移動量。
    ///
    /// ### 実行結果
    ///
    /// 以降の描画の原点が動くので、同じ引数の ``rect(_:_:_:_:)`` が別の場所に出ます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![translate(_:_:) の実行結果](https://i.gyazo.com/99b0ad0fcee4710064a4f8b5f0d59146.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(40, 40, 120, 100)
    ///       translate(180, 140)
    ///       fill(80, 170, 255)
    ///       rect(40, 40, 120, 100)
    ///       ```
    ///    }
    /// }
    public func translate(_ x: Float, _ y: Float) {
        context.translate(x, y)
    }

    /// 現在の変換に回転を適用します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（3D は z 軸まわりの回転 =
    ///   ``rotateZ(_:)`` と同じ。Processing P3D 互換。ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    ///
    /// ### 実行結果
    ///
    /// 回転の中心は原点なので、``translate(_:_:)`` で中心を移してから回します。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotate(_:) の実行結果（動き）](https://i.gyazo.com/8656acd6a04201a802b96f14ac58ac0a.gif)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       translate(width / 2, height / 2)
    ///       rotate(Float(frameCount) * 0.02)
    ///       fill(255, 190, 60)
    ///       rect(-70, -70, 140, 140)
    ///       ```
    ///    }
    /// }
    public func rotate(_ angle: Float) {
        context.rotate(angle)
    }

    /// 現在の変換に非均一スケールを適用します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（3D は z 軸を等倍とする
    ///   スケール。Processing P3D 互換。ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    ///
    /// ### 実行結果
    ///
    /// 拡大の基点は原点なので、位置も係数ぶん動きます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![scale(_:_:) の実行結果](https://i.gyazo.com/6582ff8b7eb8b8487a4d49b9a3cb4459.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(60, 60, 120, 90)
    ///       scale(1.6, 2.0)
    ///       fill(80, 170, 255)
    ///       rect(60, 60, 120, 90)
    ///       ```
    ///    }
    /// }
    public func scale(_ sx: Float, _ sy: Float) {
        context.scale(sx, sy)
    }

    /// 現在の変換に均一スケールを適用します。
    ///
    /// - Note: **2D と 3D の両方**に作用します。
    ///
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) {
        context.scale(s)
    }

    /// 現在の 2D 変換に 3x3 行列を乗算します。
    ///
    /// - Note: **2D のみ**に作用します。3D は ``applyMatrix(_:)``（`float4x4` 版）を
    ///   使用してください。P3D 意味論への統一は ``translate(_:_:)`` / ``rotate(_:)`` /
    ///   ``scale(_:_:)`` の 3 本に限っており、行列の直接適用は対象外です
    ///   （ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter matrix: 連結する 3x3 行列。
    public func applyMatrix(_ matrix: float3x3) {
        context.applyMatrix(matrix)
    }

    /// 現在の 2D 変換に Processing 形式の 6 成分アフィン行列を乗算します。
    ///
    /// 成分は行優先で、変換は `x' = n00*x + n01*y + n02`、`y' = n10*x + n11*y + n12`
    /// （Processing の `applyMatrix(n00, n01, n02, n10, n11, n12)` と互換）。
    ///
    /// - Note: **2D のみ**に作用します（ADR-0005 Amendment 2026-08-02。P3D 統一の対象外）。
    public func applyMatrix(
        _ n00: Float, _ n01: Float, _ n02: Float,
        _ n10: Float, _ n11: Float, _ n12: Float
    ) {
        context.applyMatrix(n00, n01, n02, n10, n11, n12)
    }

    /// 現在の 3D 変換に 4x4 行列を乗算します。
    ///
    /// - Note: **3D のみ**に作用します。2D は ``applyMatrix(_:)``（`float3x3` 版）を
    ///   使用してください（ADR-0005）。
    ///
    /// - Parameter matrix: 連結する 4x4 行列。
    public func applyMatrix(_ matrix: float4x4) {
        context.applyMatrix(matrix)
    }

    /// 現在の変換行列を単位行列にリセットします。
    ///
    /// - Note: **2D と 3D の両方**に作用します（``pushMatrix()``/``popMatrix()`` と
    ///   同カテゴリ。ADR-0005）。
    public func resetMatrix() {
        context.resetMatrix()
    }

    /// 現在の変換に x 軸方向のせん断（シアー）を適用します。
    ///
    /// `x' = x + tan(angle) * y`（Processing の `shearX()` と互換)。
    ///
    /// - Note: **2D のみ**に作用します。P3D 意味論への統一は
    ///   ``translate(_:_:)`` / ``rotate(_:)`` / ``scale(_:_:)`` の 3 本に限っており、
    ///   せん断は対象外です（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位のせん断角度。
    ///
    /// ### 実行結果
    ///
    /// y が大きいところほど右へずれます（下が青、上が元の形）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shearX(_:) の実行結果](https://i.gyazo.com/b3c4494e7b7eb88b4bd839c0ced4d974.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(80, 40, 140, 90)
    ///       translate(0, 150)
    ///       shearX(0.4)
    ///       fill(80, 170, 255)
    ///       rect(80, 40, 140, 90)
    ///       ```
    ///    }
    /// }
    public func shearX(_ angle: Float) {
        context.shearX(angle)
    }

    /// 現在の変換に y 軸方向のせん断（シアー）を適用します。
    ///
    /// `y' = y + tan(angle) * x`（Processing の `shearY()` と互換)。
    ///
    /// - Note: **2D のみ**に作用します。P3D 意味論への統一は
    ///   ``translate(_:_:)`` / ``rotate(_:)`` / ``scale(_:_:)`` の 3 本に限っており、
    ///   せん断は対象外です（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位のせん断角度。
    ///
    /// ### 実行結果
    ///
    /// x が大きいところほど下へずれます（右が青、左が元の形）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shearY(_:) の実行結果](https://i.gyazo.com/a5344a38d3dfaf3943dba560232c20a8.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       rect(50, 60, 120, 90)
    ///       translate(200, 0)
    ///       shearY(0.35)
    ///       fill(80, 170, 255)
    ///       rect(50, 60, 120, 90)
    ///       ```
    ///    }
    /// }
    public func shearY(_ angle: Float) {
        context.shearY(angle)
    }

    /// 2D モデル座標が描画されるスクリーン x 座標を返します。
    ///
    /// - Note: **2D のみ**。3D は ``screenX(_:_:_:)``（3 引数）を使用してください。
    public func screenX(_ x: Float, _ y: Float) -> Float {
        context.screenPosition(x, y).x
    }

    /// 2D モデル座標が描画されるスクリーン y 座標を返します。
    ///
    /// - Note: **2D のみ**。3D は ``screenY(_:_:_:)``（3 引数）を使用してください。
    public func screenY(_ x: Float, _ y: Float) -> Float {
        context.screenPosition(x, y).y
    }

    /// 3D モデル座標が描画されるスクリーン x 座標を返します。
    ///
    /// - Note: **3D のみ**に作用します（2D の座標は ``screenX(_:_:)``（2 引数）です。ADR-0005）。
    ///
    /// - Important: カメラ背後の点では値が原点対称に反転します。
    ///   ``isInFront(_:_:_:)`` で判別してください。
    public func screenX(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).x
    }

    /// 3D モデル座標が描画されるスクリーン y 座標を返します。
    ///
    /// - Note: **3D のみ**に作用します（2D の座標は ``screenY(_:_:)``（2 引数）です。ADR-0005）。
    ///
    /// - Important: カメラ背後の点では値が原点対称に反転します。
    ///   ``isInFront(_:_:_:)`` で判別してください。
    public func screenY(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).y
    }

    /// 3D モデル座標の正規化デバイス深度（0...1）を返します。
    ///
    /// 手前ほど小さい値になります（Processing の `screenZ()` 相当）。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画に深度はありません。ADR-0005）。
    ///
    /// - Important: 0...1 に収まるのは点が視錐台の内側にあるときだけです。
    ///   カメラ背後では 1 を超え、カメラとニア平面のあいだでは負になります。
    ///   ``isInFront(_:_:_:)`` で背後を弾いてから使ってください。
    public func screenZ(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.screenPosition(x, y, z).z
    }

    /// 3D モデル座標の点がカメラ平面より前にあるかを返します。
    ///
    /// ``screenX(_:_:_:)`` / ``screenY(_:_:_:)`` / ``screenZ(_:_:_:)`` は
    /// カメラ背後の点に対して反転した値を返し、戻り値だけでは前方の点と区別できません。
    /// ラベル配置やカリングの前にこの判定を挟んでください。
    ///
    /// ```swift
    /// if isInFront(px, py, pz) {
    ///     text("label", screenX(px, py, pz), screenY(px, py, pz))
    /// }
    /// ```
    ///
    /// - Note: **3D のみ**に作用します（カメラ平面を持つのは 3D だけです。ADR-0005）。
    ///
    /// - Note: true は「反転していない」ことだけを保証し、「画面内にある」ことは
    ///   保証しません。正射影では反転が起きないため常に true を返します。
    public func isInFront(_ x: Float, _ y: Float, _ z: Float) -> Bool {
        context.isInFront(x, y, z)
    }

    /// 現在の変換を通した 3D モデル座標のワールド x 座標を返します。
    ///
    /// 変換スタックに積んだ `translate` / `rotateX/Y/Z` / `scale` の結果、その点が
    /// ワールド空間のどこに来るかを返します（Processing の `modelX()` 相当）。
    /// ``pushMatrix()`` 〜 ``popMatrix()`` の中で位置を控えておき、抜けた後に同じ場所へ
    /// 別のものを置く、という使い方が典型です。
    ///
    /// ```swift
    /// pushMatrix()
    /// translate(100, 50, 0)
    /// rotateY(angle)
    /// translate(0, 0, 60)
    /// // 回転の先端がワールドのどこに来るかを控える
    /// let wx = modelX(0, 0, 0)
    /// let wy = modelY(0, 0, 0)
    /// let wz = modelZ(0, 0, 0)
    /// popMatrix()
    ///
    /// pushMatrix()
    /// translate(wx, wy, wz)   // 変換スタックの外から同じ場所へ置ける
    /// box(10)
    /// popMatrix()
    /// ```
    ///
    /// - Note: **3D のみ**。スクリーン座標（ピクセル）が欲しいときは
    ///   ``screenX(_:_:_:)`` を使ってください。
    /// - Important: 返るのは**ワールド座標**で、カメラには依存しません。
    ///   ``camera(eye:center:up:)`` や ``perspective(fov:near:far:)`` を変えても
    ///   値は変わりません（Processing の `modelX()` と同じ意味論）。
    public func modelX(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).x
    }

    /// 現在の変換を通した 3D モデル座標のワールド y 座標を返します。
    ///
    /// - Note: **3D のみ**。用例と注意点は ``modelX(_:_:_:)`` を参照してください。
    /// - Important: カメラには依存しません（Processing の `modelY()` と同じ意味論）。
    public func modelY(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).y
    }

    /// 現在の変換を通した 3D モデル座標のワールド z 座標を返します。
    ///
    /// - Note: **3D のみ**。用例と注意点は ``modelX(_:_:_:)`` を参照してください。
    ///   スクリーン深度（0...1）が欲しいときは ``screenZ(_:_:_:)`` です。
    /// - Important: カメラには依存しません（Processing の `modelZ()` と同じ意味論）。
    public func modelZ(_ x: Float, _ y: Float, _ z: Float) -> Float {
        context.modelPosition(x, y, z).z
    }

    // MARK: 2D Shapes

    /// 矩形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の直方体は ``box(_:_:_:)``、平面は ``plane(_:_:)`` です。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///
    /// ### 実行結果
    ///
    /// x, y の解釈は ``rectMode(_:)`` で変わります（既定は左上隅）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:) の実行結果](https://i.gyazo.com/353e3c185f55a74b535e66da3cd85262.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       rect(60, 90, 160, 180)
    ///       ```
    ///    }
    /// }
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.rect(x, y, w, h)
    }

    /// 均一な角丸半径の角丸矩形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D に角丸のプリミティブはありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - r: 角丸半径。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:_:) の実行結果](https://i.gyazo.com/0c7c14f4b93a5a76ae0345d776144159.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       rect(120, 90, 240, 180, 40)
    ///       ```
    ///    }
    /// }
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        context.rect(x, y, w, h, r)
    }

    /// 各角に個別の角丸半径を持つ角丸矩形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D に角丸のプリミティブはありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - tl: 左上の角丸半径。
    ///   - tr: 右上の角丸半径。
    ///   - br: 右下の角丸半径。
    ///   - bl: 左下の角丸半径。
    ///
    /// ### 実行結果
    ///
    /// 半径は左上・右上・右下・左下の順に指定します。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rect(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/41bbd3412e6f36396c93f0b52c9a6384.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       rect(
    ///           120, 90, 240, 180,
    ///           60, 0, 60, 0
    ///       )
    ///       ```
    ///    }
    /// }
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        context.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// リニアグラデーション矩形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D のグラデーションはシェーダか頂点カラーで作ります。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - c1: 開始色。
    ///   - c2: 終了色。
    ///   - axis: グラデーションの方向。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![linearGradient(_:_:_:_:_:_:axis:) の実行結果](https://i.gyazo.com/23aa77a3c8669991320fadbb7db44090.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       linearGradient(
    ///           60, 60, 360, 240,
    ///           Color(r: 1, g: 0.75, b: 0.24),
    ///           Color(r: 0.31, g: 0.24, b: 0.63)
    ///       )
    ///       ```
    ///    }
    /// }
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        context.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// 放射状グラデーション円を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D のグラデーションはシェーダか頂点カラーで作ります。ADR-0005）。
    ///
    /// - Parameters:
    ///   - cx: 中心の x 座標。
    ///   - cy: 中心の y 座標。
    ///   - radius: 外側の半径。
    ///   - innerColor: 中心の色。
    ///   - outerColor: 外周の色。
    ///   - segments: 滑らかさのためのセグメント数。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![radialGradient(_:_:_:_:_:segments:) の実行結果](https://i.gyazo.com/b0ed7cd91d7755617b9d404847fe07f5.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       radialGradient(
    ///           240, 180, 150,
    ///           Color(r: 1, g: 0.94, b: 0.78),
    ///           Color(r: 0.16, g: 0.16, b: 0.35)
    ///       )
    ///       ```
    ///    }
    /// }
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        context.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// 楕円を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の球は ``sphere(_:detail:)`` です。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅（水平方向の直径）。
    ///   - h: 高さ（垂直方向の直径）。
    ///
    /// ### 実行結果
    ///
    /// x, y の解釈は ``ellipseMode(_:)`` で変わります（既定は中心）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ellipse(_:_:_:_:) の実行結果](https://i.gyazo.com/53a1b556de5a248e28f134d21f84ab8b.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       ellipse(240, 180, 260, 150)
    ///       ```
    ///    }
    /// }
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.ellipse(x, y, w, h)
    }

    /// 円を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の球は ``sphere(_:detail:)`` です。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: 中心の x 座標。
    ///   - y: 中心の y 座標。
    ///   - diameter: 円の直径。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![circle(_:_:_:) の実行結果](https://i.gyazo.com/5db1a81abf5604a4ee8a316406fc5049.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(80, 170, 255)
    ///       noStroke()
    ///       circle(width / 2, height / 2, 200)
    ///       ```
    ///    }
    /// }
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        context.circle(x, y, diameter)
    }

    /// 複数の円を一括描画します。
    ///
    /// `circle()` を多数回呼ぶ代わりに、位置・直径・色を持つ ``CircleInstance`` 配列を
    /// compact instancing path でまとめて描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の一括描画は ``drawInstanced(_:transforms:)`` です。ADR-0005）。
    ///
    /// - Parameter instances: 描画する円インスタンス。
    public func circles(_ instances: [CircleInstance]) {
        context.circles(instances)
    }

    /// GPU バッファ上の円インスタンスを一括描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の一括描画は ``drawInstanced(_:transforms:)`` です。ADR-0005）。
    ///
    /// - Parameters:
    ///   - instances: ``CircleInstance`` を保持する GPU バッファ。
    ///   - count: 描画するインスタンス数。省略時はバッファ全体。
    public func circles(_ instances: GPUBuffer<CircleInstance>, count: Int? = nil) {
        context.circles(instances, count: count)
    }

    /// 正方形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の立方体は ``box(_:)`` です。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - size: 辺の長さ。
    ///
    /// ### 実行結果
    ///
    /// x, y の解釈は ``rectMode(_:)`` に従います（既定は左上隅）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![square(_:_:_:) の実行結果](https://i.gyazo.com/e39d66e012449b14a5ae4cdb4d346578.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       square(160, 100, 160)
    ///       ```
    ///    }
    /// }
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        context.square(x, y, size)
    }

    /// 4つの頂点で定義される四角形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D で任意の四角形を組むには ``beginShape3D(_:)`` を使います。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x1: 第1頂点の x 座標。
    ///   - y1: 第1頂点の y 座標。
    ///   - x2: 第2頂点の x 座標。
    ///   - y2: 第2頂点の y 座標。
    ///   - x3: 第3頂点の x 座標。
    ///   - y3: 第3頂点の y 座標。
    ///   - x4: 第4頂点の x 座標。
    ///   - y4: 第4頂点の y 座標。
    ///
    /// ### 実行結果
    ///
    /// 頂点は順に結ばれるので、並べる順で凸にも凹にもなります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![quad(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/dc84d016cc71fa60501d786d01d82692.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(150, 220, 120)
    ///       noStroke()
    ///       quad(
    ///           120, 70, 400, 120,
    ///           360, 300, 90, 250
    ///       )
    ///       ```
    ///    }
    /// }
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 2点間に線を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の線は ``beginShape3D(_:)`` に ``ShapeMode/lines`` を渡します。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x1: 始点の x 座標。
    ///   - y1: 始点の y 座標。
    ///   - x2: 終点の x 座標。
    ///   - y2: 終点の y 座標。
    ///
    /// ### 実行結果
    ///
    /// 太さは ``strokeWeight(_:)``、端点の形は ``strokeCap(_:)`` で変わります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![line(_:_:_:_:) の実行結果](https://i.gyazo.com/20e8d9c58aedcf6c2eead71cb4fca8e7.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(6)
    ///       line(80, 280, 400, 80)
    ///       ```
    ///    }
    /// }
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        context.line(x1, y1, x2, y2)
    }

    /// 3つの頂点で定義される三角形を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の三角形は ``beginShape3D(_:)`` で組みます。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x1: 第1頂点の x 座標。
    ///   - y1: 第1頂点の y 座標。
    ///   - x2: 第2頂点の x 座標。
    ///   - y2: 第2頂点の y 座標。
    ///   - x3: 第3頂点の x 座標。
    ///   - y3: 第3頂点の y 座標。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![triangle(_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/9f04166a0245ba36661e30099eae1e45.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 120, 90)
    ///       noStroke()
    ///       triangle(240, 60, 400, 300, 80, 300)
    ///       ```
    ///    }
    /// }
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        context.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// 座標タプルの配列からポリゴンを描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D は ``beginShape3D(_:)`` で組みます。ADR-0005）。
    ///
    /// - Parameter points: `(x, y)` タプルとしてのポリゴン頂点。
    public func polygon(_ points: [(Float, Float)]) {
        context.polygon(points)
    }

    /// ``Vec2`` 配列からポリゴンを描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D は ``beginShape3D(_:)`` で組みます。ADR-0005）。
    ///
    /// - Parameter points: ポリゴン頂点。
    public func polygon(_ points: [Vec2]) {
        context.polygon(points)
    }

    /// 円弧を描画します（`stopAngle` は `startAngle` より大きいこと。2π 超は 1 周にクランプ）。
    ///
    /// - Note: **2D のみ**に作用します（3D に対応するプリミティブはありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: 円弧の中心の x 座標。
    ///   - y: 円弧の中心の y 座標。
    ///   - w: 円弧の外接楕円の幅。
    ///   - h: 円弧の外接楕円の高さ。
    ///   - startAngle: ラジアン単位の開始角度。
    ///   - stopAngle: ラジアン単位の終了角度。`startAngle` 以下なら何も描きません。
    ///   - mode: 円弧の描画モード。省略時は Processing のデフォルトと同じく
    ///     「扇形の fill + 弧のみの stroke」（``ArcMode/default``）。明示 ``ArcMode/open`` の
    ///     fill は弦で閉じた弓形になる点が省略時と異なる。
    ///
    /// 角度は Processing と同じく描画前に正規化されます。`stopAngle <= startAngle` は何も描かず
    /// （逆回りには描かない）、範囲が 2π を超える場合は 0〜2π へクランプします（重ね描きしない）。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![arc(_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/66c138c57b6838b7a60c9d58b222b5eb.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 120, 140)
    ///       stroke(255)
    ///       strokeWeight(3)
    ///       let sweep = Float.pi * 1.2
    ///       arc(240, 180, 220, 220, 0, sweep)
    ///       ```
    ///    }
    /// }
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .default
    ) {
        context.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// 3次ベジェ曲線を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D のベジェ曲線はありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x1: 始点の x 座標。
    ///   - y1: 始点の y 座標。
    ///   - cx1: 第1制御点の x 座標。
    ///   - cy1: 第1制御点の y 座標。
    ///   - cx2: 第2制御点の x 座標。
    ///   - cy2: 第2制御点の y 座標。
    ///   - x2: 終点の x 座標。
    ///   - y2: 終点の y 座標。
    ///
    /// ### 実行結果
    ///
    /// 制御点（灰色）は曲線上には乗らず、両端から引っぱる向きだけを決めます。
    ///
    /// <!-- reference-shot -->
    ///
    /// ```swift
    /// background(24)
    /// noFill()
    /// stroke(120, 230, 180)
    /// strokeWeight(4)
    /// bezier(60, 280, 140, 40, 340, 320, 420, 80)
    ///
    /// // 端点と、それを引っぱっている制御点を結んで見せる
    /// stroke(130)
    /// strokeWeight(1)
    /// line(60, 280, 140, 40)
    /// line(420, 80, 340, 320)
    /// strokeWeight(12)
    /// point(140, 40)
    /// point(340, 320)
    /// ```
    ///
    /// ![bezier(_:_:_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/0b721460f802e496b860f974378c500c.png)
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        context.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// 単一の点を描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D の点は ``beginShape3D(_:)`` に ``ShapeMode/points`` を渡します。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///
    /// ### 実行結果
    ///
    /// 点の大きさは ``strokeWeight(_:)``、色は `stroke()` で決まります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![point(_:_:) の実行結果](https://i.gyazo.com/3878c966403fc6876992923c40bb27bd.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       stroke(255, 190, 60)
    ///       strokeWeight(12)
    ///       for i in 0..<9 {
    ///           let x = 80 + Float(i) * 40
    ///           point(x, 180 - Float(i % 3) * 50)
    ///       }
    ///       ```
    ///    }
    /// }
    public func point(_ x: Float, _ y: Float) {
        context.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    /// カスタムシェイプの頂点記録を開始します。
    ///
    /// - Note: **2D のみ**に作用します（3D のカスタムシェイプは ``beginShape3D(_:)`` です。ADR-0005）。
    ///
    /// - Parameter mode: シェイプモード（例: polygon、triangles、lines）。
    ///
    /// ### 実行結果
    ///
    /// ``vertex(_:_:)`` で頂点を並べ、``endShape(_:)`` で閉じて描きます。
    /// 星の順（5 点を 2 つ飛ばし）に並べると辺どうしが交差しますが、塗りは
    /// nonzero winding 規則なので五芒星になります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![beginShape(_:) の実行結果](https://i.gyazo.com/d965e3aa16851653671ff363b8edd959.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       beginShape()
    ///       vertex(240, 60)
    ///       vertex(330, 300)
    ///       vertex(90, 150)
    ///       vertex(390, 150)
    ///       vertex(150, 300)
    ///       endShape(.close)
    ///       ```
    ///    }
    /// }
    public func beginShape(_ mode: ShapeMode = .polygon) {
        context.beginShape(mode)
    }

    /// 現在のシェイプに 2D 頂点を追加します。
    ///
    /// - Note: 作用先は**記録中のシェイプ**が決めます。``beginShape(_:)`` で始めていれば
    ///   2D へ、``beginShape3D(_:)`` で始めていれば z = 0 の 3D 頂点として流れます
    ///   （Processing 互換。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///
    /// ### 実行結果
    ///
    /// ``endShape(_:)`` を ``CloseMode/open`` のまま閉じないと折れ線になります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![vertex(_:_:) の実行結果](https://i.gyazo.com/050fa166d5c66c43957cb13a43d68b44.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(6)
    ///       beginShape()
    ///       vertex(70, 260)
    ///       vertex(150, 110)
    ///       vertex(240, 230)
    ///       vertex(330, 90)
    ///       vertex(410, 240)
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func vertex(_ x: Float, _ y: Float) {
        context.vertex(x, y)
    }

    /// 現在のシェイプに頂点カラー付き 2D 頂点を追加します。
    ///
    /// - Note: 作用先は**記録中のシェイプ**が決めます。``beginShape(_:)`` で始めていれば
    ///   2D へ、``beginShape3D(_:)`` で始めていれば z = 0 の 3D 頂点として流れます
    ///   （ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        context.vertex(x, y, color)
    }

    /// 現在のシェイプにテクスチャ座標付き 2D 頂点を追加します。
    ///
    /// - Note: 作用先は**記録中のシェイプ**が決めます。``beginShape(_:)`` で始めていれば
    ///   2D へ流れます。``beginShape3D(_:)`` の記録中は UV を落として z = 0 の 3D 頂点に
    ///   なり、初回だけ警告します（ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - u: 水平テクスチャ座標。
    ///   - v: 垂直テクスチャ座標。
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, u, v)
    }

    /// 現在のシェイプに3次ベジェ頂点を追加します。
    ///
    /// - Note: **2D のみ**に作用します（3D のシェイプにベジェ頂点はありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - cx1: 第1制御点の x 座標。
    ///   - cy1: 第1制御点の y 座標。
    ///   - cx2: 第2制御点の x 座標。
    ///   - cy2: 第2制御点の y 座標。
    ///   - x: アンカーポイントの x 座標。
    ///   - y: アンカーポイントの y 座標。
    ///
    /// ### 実行結果
    ///
    /// 直前の頂点が始点になるので、``vertex(_:_:)`` を 1 つ置いてから呼びます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![bezierVertex(_:_:_:_:_:_:) の実行結果](https://i.gyazo.com/96c2d0ca7b953a80922e8477d611243e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(255, 190, 60)
    ///       strokeWeight(4)
    ///       beginShape()
    ///       vertex(80, 260)
    ///       bezierVertex(
    ///           120, 60, 360, 60, 400, 260
    ///       )
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        context.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// 現在のシェイプに Catmull-Rom スプライン頂点を追加します。
    ///
    /// - Note: **2D のみ**に作用します（3D のシェイプにスプライン頂点はありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///
    /// ### 実行結果
    ///
    /// 最初と最後の点は曲線の向きを決める制御点なので、同じ座標を 2 回置きます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![curveVertex(_:_:) の実行結果](https://i.gyazo.com/46e0b074f4363c0b55f426584e360940.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       noFill()
    ///       stroke(80, 170, 255)
    ///       strokeWeight(4)
    ///       beginShape()
    ///       curveVertex(60, 240)
    ///       curveVertex(60, 240)
    ///       curveVertex(180, 120)
    ///       curveVertex(300, 280)
    ///       curveVertex(420, 140)
    ///       curveVertex(420, 140)
    ///       endShape()
    ///       ```
    ///    }
    /// }
    public func curveVertex(_ x: Float, _ y: Float) {
        context.curveVertex(x, y)
    }

    /// カーブ補間のセグメント数を設定します。
    ///
    /// - Note: **2D のみ**に作用します（``curveVertex(_:_:)`` /
    ///   ``curve(_:_:_:_:_:_:_:_:)`` 用で、3D には効きません。ADR-0005）。
    ///
    /// - Parameter n: カーブの詳細度。
    public func curveDetail(_ n: Int) {
        context.curveDetail(n)
    }

    /// Catmull-Rom スプラインカーブの張り具合を設定します。
    ///
    /// - Note: **2D のみ**に作用します（``curveVertex(_:_:)`` /
    ///   ``curve(_:_:_:_:_:_:_:_:)`` 用で、3D には効きません。ADR-0005）。
    ///
    /// - Note: `-5.0` 〜 `5.0` が目安です。範囲外の値も受け付けます（Processing と同じく
    ///   clamp しません）が、曲線が制御点から大きく外れます。
    ///
    /// - Parameter t: 張り値（0 = デフォルト、1 = 直線）。
    public func curveTightness(_ t: Float) {
        context.curveTightness(t)
    }

    /// 現在のシェイプ内にコンター（穴）の定義を開始します（2D シェイプ専用）。
    ///
    /// `beginShape3D()` で組む 3D シェイプでは穴を開けられません（呼んでも何も起きず、
    /// 初回だけ警告が出ます）。3D で穴の開いた面が要るときは、内側と外側のあいだの
    /// 輪帯を自分で三角形に割ってください。
    ///
    /// - Note: **2D のみ**に作用します（``beginShape3D(_:)`` の記録中は何もせず、
    ///   初回だけ警告します。#736 / ADR-0005）。
    ///
    /// ### 実行結果
    ///
    /// 穴は外周と逆まわりに並べます。``endContour()`` で閉じてから
    /// ``endShape(_:)`` を呼びます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![beginContour() の実行結果](https://i.gyazo.com/0589e9f453959e2667e5a33fb94cf8a4.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(24)
    ///       fill(255, 190, 60)
    ///       noStroke()
    ///       beginShape()
    ///       vertex(100, 70)
    ///       vertex(380, 70)
    ///       vertex(380, 290)
    ///       vertex(100, 290)
    ///       beginContour()
    ///       vertex(190, 130)
    ///       vertex(190, 230)
    ///       vertex(290, 230)
    ///       vertex(290, 130)
    ///       endContour()
    ///       endShape(.close)
    ///       ```
    ///    }
    /// }
    public func beginContour() {
        context.beginContour()
    }

    /// 現在のコンター定義を終了します（2D シェイプ専用）。
    ///
    /// - Note: **2D のみ**に作用します（``beginShape3D(_:)`` の記録中は何もせず、
    ///   初回だけ警告します。#736 / ADR-0005）。
    public func endContour() {
        context.endContour()
    }

    /// 4点を通る Catmull-Rom スプラインカーブを描画します。
    ///
    /// - Note: **2D のみ**に作用します（3D のスプライン曲線はありません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x1: 第1制御点の x 座標。
    ///   - y1: 第1制御点の y 座標。
    ///   - x2: 始点の x 座標。
    ///   - y2: 始点の y 座標。
    ///   - x3: 終点の x 座標。
    ///   - y3: 終点の y 座標。
    ///   - x4: 第2制御点の x 座標。
    ///   - y4: 第2制御点の y 座標。
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 現在のシェイプの記録を終了し描画します。
    ///
    /// - Note: 作用先は**記録中のシェイプ**が決めます。``beginShape3D(_:)`` で始めていた
    ///   シェイプもこれで閉じられます（``endShape3D(_:)`` と同じ結果。ADR-0005）。
    ///
    /// - Note: 自己交差する頂点列（五芒星など）の塗りは **nonzero winding** 規則に従います
    ///   （Processing / p5.js と同じ）。巻き数が 0 でない領域が塗られるので、五芒星は
    ///   中央の五角形まで塗られたべた塗りの星になります。
    ///
    /// - Parameter close: 最後の頂点と最初の頂点を接続してシェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        context.endShape(close)
    }

    // MARK: - Clipping

    /// 以降の描画を指定した矩形にクリッピングします。
    ///
    /// - Note: **2D のみ**に作用します（3D の描画はクリップされません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: クリップ領域の x 座標。
    ///   - y: クリップ領域の y 座標。
    ///   - w: クリップ領域の幅。
    ///   - h: クリップ領域の高さ。
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.beginClip(x, y, w, h)
    }

    /// 現在のクリップ領域を終了し、前の状態に復元します。
    ///
    /// - Note: **2D のみ**に作用します（3D の描画はクリップされません。ADR-0005）。
    public func endClip() {
        context.endClip()
    }
}
