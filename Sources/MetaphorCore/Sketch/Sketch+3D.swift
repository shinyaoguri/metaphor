// MARK: - 3D Drawing (Camera, Lighting, Material, Shapes, Transform)

extension Sketch {

    // MARK: 3D Custom Shapes

    /// 3D カスタムシェイプの頂点記録を開始します。
    ///
    /// 現在の色は各頂点に 1 回だけ掛かります。`beginShape3D` と `endShape3D` の間で
    /// 色を変えると、その時点以降の頂点だけが新しい色になります（頂点ごとの色づけ）。
    /// 使われるのは面モード（`.polygon` / `.triangles` など）では `fill`、
    /// **`.lines` / `.points` では `stroke`** です（Processing の LINES / POINTS と同じ。
    /// `noStroke()` のときは `fill` に戻ります）。
    ///
    /// - Parameter mode: シェイプモード（例: polygon、triangles、lines）。
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        context.beginShape3D(mode)
    }

    /// 現在のシェイプに 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        context.vertex(x, y, z)
    }

    /// 現在のシェイプに頂点カラー付き 3D 頂点を追加します。
    ///
    /// 与えた色は現在の `fill` に左右されず、そのまま出ます。
    /// `texture()` を貼ったシェイプでは頂点カラーは使われません（テクスチャの色が出ます）。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        context.vertex(x, y, z, color)
    }

    /// 現在のシェイプにテクスチャ座標付き 3D 頂点を追加します。
    ///
    /// `texture(_:)` で画像を設定したシェイプでのみ効果があります。テクスチャ未設定の場合は
    /// UV が無視され、通常の fill で塗られます。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - z: z 座標。
    ///   - u: 水平テクスチャ座標（0.0〜1.0 に正規化）。
    ///   - v: 垂直テクスチャ座標（0.0〜1.0 に正規化）。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, z, u, v)
    }

    /// 以降の 3D 頂点の法線ベクトルを設定します。
    ///
    /// `endShape3D()` まで持続します。リテインドな ``MShape/normal(_:_:_:)`` も
    /// 同じ範囲です（#876）。頂点ごとに違う法線を入れたいなら頂点ごとに呼びます。
    ///
    /// - Parameters:
    ///   - nx: 法線の x 成分。
    ///   - ny: 法線の y 成分。
    ///   - nz: 法線の z 成分。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        context.normal(nx, ny, nz)
    }

    /// 現在の 3D シェイプの記録を終了し描画します。
    ///
    /// - Parameter close: 最後の頂点と最初の頂点を接続してシェイプを閉じるかどうか。
    public func endShape3D(_ close: CloseMode = .open) {
        context.endShape3D(close)
    }

    // MARK: 3D Camera

    /// eye、center、up ベクトルで 3D カメラを設定します。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はカメラの影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - eye: カメラの位置。
    ///   - center: カメラが注視する点。
    ///   - up: 上方向ベクトル。
    ///
    /// ### 実行結果
    ///
    /// 既定カメラはキャンバス左上を原点に置くピクセル空間ですが、`camera()` を呼ぶと
    /// `center` を中心に見る座標系へ移ります（下の例では原点に置いた箱がそのまま
    /// 画面中央に来るので、``translate(_:_:_:)`` が要りません）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![camera(eye:center:up:) の実行結果](https://i.gyazo.com/300bb909ffb972fba5ac4e2ff4589779.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 200, 255)
    ///       camera(
    ///           eye: SIMD3(190, -150, 330),
    ///           center: SIMD3(0, 0, 0)
    ///       )
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        context.camera(eye: eye, center: center, up: up)
    }

    /// 透視投影を設定します。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画は投影の影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - fov: ラジアン単位の視野角。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    ///
    /// ### 実行結果
    ///
    /// 同じ大きさの箱を奥へ 3 つ並べると、遠いものほど小さく写ります。`fov` を狭めると
    /// 望遠レンズのように遠近が浅くなります。同じ配置を平行投影で撮ったものが
    /// ``ortho(left:right:bottom:top:near:far:)`` にあり、並べて見比べられます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![perspective(fov:near:far:) の実行結果](https://i.gyazo.com/8f6220f6e61ce88a2b720b1c4dac36fd.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       perspective(fov: PI / 3)
    ///       translate(width / 2, height / 2, 0)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               Float(i) * 120 - 120,
    ///               0,
    ///               Float(i) * -170
    ///           )
    ///           box(90)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        context.perspective(fov: fov, near: near, far: far)
    }

    /// 正射影を設定します。
    ///
    /// 省略した面は**既定カメラと噛み合う範囲**で埋まります。正射影は**ビュー空間**に
    /// 効くのに対し既定カメラはキャンバス中央を注視しているため、省略時の範囲も原点
    /// （＝画面中央）を挟む形になります。これで `ortho()` を単独で呼ぶだけで、2D と
    /// 同じピクセル座標のまま平行投影に切り替わります（#777）。
    ///
    /// - Important: `bottom` / `top` は投影行列の規約どおり「ビュー空間の y が
    ///   **小さい**側が `bottom`」です。metaphor の y は 2D と同じく画面下向きなので、
    ///   `bottom` は画面の**上端**、`top` は**下端**に対応します。上下を逆に渡すと
    ///   絵が上下反転します。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画は投影の影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - left: 左クリッピング面（`nil` のときは `-width / 2`）。
    ///   - right: 右クリッピング面（`nil` のときは `width / 2`）。
    ///   - bottom: 下クリッピング面（`nil` のときは `-height / 2`）。
    ///   - top: 上クリッピング面（`nil` のときは `height / 2`）。
    ///   - near: ニアクリッピング面の距離（`nil` のときは既定カメラ距離の -10 倍）。
    ///   - far: ファークリッピング面の距離（`nil` のときは既定カメラ距離の 10 倍）。
    ///
    /// ### 実行結果
    ///
    /// ``perspective(fov:near:far:)`` と**同じ配置**を平行投影で撮ったものです。
    /// 奥行きをずらしても大きさが変わらないので、3 つの箱が同じ寸法で並びます。
    ///
    /// 下の例は範囲を明示していますが、既定カメラのままなら `ortho()` だけでも
    /// 中央に同じ大きさで写ります（明示するのは写す範囲を絞りたいときです）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ortho(left:right:bottom:top:near:far:) の実行結果](https://i.gyazo.com/76e24bd04603f61a942af99c875580d3.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 220, 120)
    ///       ortho(
    ///           left: -width / 2,
    ///           right: width / 2,
    ///           bottom: -height / 2,
    ///           top: height / 2
    ///       )
    ///       translate(width / 2, height / 2, 0)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               Float(i) * 120 - 120,
    ///               0,
    ///               Float(i) * -170
    ///           )
    ///           box(90)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float? = nil, far: Float? = nil
    ) {
        context.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    /// デフォルトライティング（ディレクショナルライトとアンビエントライト）を有効にします。
    ///
    /// アンビエントは `colorMode` のレンジの 30%（既定レンジ 0〜255 なら
    /// `ambientLight(76.5)` 相当）に設定されます。ライトを個別に足す場合も、
    /// `ambientLight()` を呼んでいなければ最初のライト追加時に同じ値が入ります。
    ///
    /// 既定リグの灯は**右上手前**から差します（``directionalLight(_:_:_:color:intensity:)``
    /// でいう `(-0.5, 1, -0.8)`）。``enableShadows(resolution:)`` の影もこの向きに落ちます。
    ///
    /// 既定リグの灯は `intensity` 0.7 で、Blinn-Phong（既定）に合わせた明るさです。
    /// PBR（``pbr(_:)``）では直接光が `albedo / π` で沈むため、同じリグでも
    /// **3〜4 割暗く**なります（96×96 の球で実測: Blinn-Phong 80.4 / PBR 51.2）。
    /// PBR で立体感が要るときは ``directionalLight(_:_:_:color:intensity:)`` を
    /// `intensity` 付きで自分で置いてください。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はライティングの影響を受けません。ADR-0005）。
    ///
    /// ### 実行結果
    ///
    /// ライトが 1 つも無いと陰影の計算そのものが省かれ、``fill(_:_:_:_:)`` の色で
    /// べた塗りになります（左）。ライトは描画のたびに評価されるので、同じフレームの
    /// 途中で足せば以降の形状だけが照らされます（右）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![lights() の実行結果](https://i.gyazo.com/016885f45d91c0122a6c2c8718c53d7d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       lights()
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func lights() {
        context.lights()
    }

    /// すべてのライトを無効にします。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    public func noLights() {
        context.noLights()
    }

    /// ディレクショナルライトを追加します。
    ///
    /// 指定するのは「光が**進む**向き」で、y 軸は Processing と同じく画面下向きです。
    /// つまり `directionalLight(0, 1, 0)` が「真上から差す光」、`(0, -1, 0)` は
    /// 「真下から差す光」になります（`enableShadows()` 時の影の向きもこれに従う）。
    ///
    /// `intensity` は色に掛かる強度倍率です。PBR（``pbr(_:)``）の直接光は
    /// `albedo / π` で減衰し、環境光は ``ambientLight(_:)`` のフォールバックしか
    /// 無いため、**単灯で立体感を出すには 2〜4 程度**が要ります。
    /// Blinn-Phong（既定）では 1.0 のままで従来どおりの明るさです。
    ///
    /// ```swift
    /// pbr(true)
    /// directionalLight(-0.4, 1, -0.6, intensity: 3)   // キーライトを持ち上げる
    /// ```
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はライティングの影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: ライト方向の x 成分。
    ///   - y: ライト方向の y 成分。
    ///   - z: ライト方向の z 成分。
    ///   - color: ライトの色（デフォルト白）。
    ///   - intensity: ライトの強度倍率（デフォルト 1.0）。
    ///
    /// ### 実行結果
    ///
    /// 光の x 成分だけを -1 / 0 / +1 と変えた 3 つ。方向光は位置を持たないので、
    /// どこに置いた球でも同じ向きから当たります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![directionalLight(_:_:_:color:intensity:) の実行結果](https://i.gyazo.com/91028fa6f248fab585f01a0e5fcc3d8f.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///
    ///       for i in 0..<3 {
    ///           noLights()
    ///           ambientLight(40)
    ///           directionalLight(
    ///               Float(i - 1), 1, -0.6
    ///           )
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func directionalLight(
        _ x: Float, _ y: Float, _ z: Float, color: Color = .white, intensity: Float = 1.0
    ) {
        context.directionalLight(x, y, z, color: color, intensity: intensity)
    }

    /// 指定位置にポイントライトを追加します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: ライト位置の x 座標。
    ///   - y: ライト位置の y 座標。
    ///   - z: ライト位置の z 座標。
    ///   - color: ライトの色。
    ///   - falloff: 減衰係数。
    ///   - intensity: ライトの強度倍率（デフォルト 1.0）。PBR で単灯のときは
    ///     1.0 より大きい値が要ります（``directionalLight(_:_:_:color:intensity:)`` 参照）。
    ///
    /// ### 実行結果
    ///
    /// 方向光と違って**位置**を持つので、灯に近い球ほど明るくなります
    /// （灯はキャンバス中央の手前に 1 つだけ置いています）。`falloff` は距離減衰の
    /// 係数で、**線形項にそのまま・二次項にその 1/10** が入ります。ピクセル空間では
    /// 距離が数百のオーダーになるため、既定の 0.1 のままだとほぼ光が届きません。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![pointLight(_:_:_:color:falloff:intensity:) の実行結果](https://i.gyazo.com/0bc0a58c490fe49b0292db8bc80817dd.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///       ambientLight(30)
    ///       pointLight(
    ///           240, 180, 130,
    ///           falloff: 0.004,
    ///           intensity: 3
    ///       )
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           sphere(70)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1,
        intensity: Float = 1.0
    ) {
        context.pointLight(x, y, z, color: color, falloff: falloff, intensity: intensity)
    }

    /// 指定位置・方向にスポットライトを追加します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameters:
    ///   - x: ライト位置の x 座標。
    ///   - y: ライト位置の y 座標。
    ///   - z: ライト位置の z 座標。
    ///   - dirX: ライト方向の x 成分。
    ///   - dirY: ライト方向の y 成分。
    ///   - dirZ: ライト方向の z 成分。
    ///   - angle: ラジアン単位のコーン角度。
    ///   - falloff: 減衰係数。
    ///   - color: ライトの色。
    ///   - intensity: ライトの強度倍率（デフォルト 1.0）。PBR で単灯のときは
    ///     1.0 より大きい値が要ります（``directionalLight(_:_:_:color:intensity:)`` 参照）。
    ///
    /// ### 実行結果
    ///
    /// 正対させた ``plane(_:_:)`` を手前から照らすと、`angle` で決まる円錐の断面が
    /// 円として切り取られます。`falloff` は ``pointLight(_:_:_:color:falloff:intensity:)``
    /// と同じ距離減衰で、ピクセル空間では既定の 0.01 でもほぼ光が届きません。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![spotLight(_:_:_:_:_:_:angle:falloff:color:intensity:) の実行結果](https://i.gyazo.com/1fe96b4c5fb912f33eb124a9faca0af2.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(220)
    ///       ambientLight(20)
    ///       spotLight(
    ///           240, 180, 300,
    ///           0, 0, -1,
    ///           angle: PI / 7,
    ///           falloff: 0.0005,
    ///           intensity: 4
    ///       )
    ///       translate(width / 2, height / 2, 0)
    ///       plane(460, 340)
    ///       ```
    ///    }
    /// }
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white,
        intensity: Float = 1.0
    ) {
        context.spotLight(
            x, y, z, dirX, dirY, dirZ,
            angle: angle, falloff: falloff, color: color, intensity: intensity
        )
    }

    /// グレースケール値でアンビエントライトの強度を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    /// `ambientLight(0.35)` のような 0〜1 のつもりの値はほぼ真っ暗になります
    /// （既定レンジなら `ambientLight(90)` 相当を指定する）。
    ///
    /// `lights()` や最初のライト追加で自動的に入る既定アンビエントは
    /// **レンジの 30%**（既定レンジなら `ambientLight(76.5)`）です。
    /// 既定と同じ明るさを明示したいときは `ambientLight(0.3)` ではなく
    /// `ambientLight(76.5)` と書きます。
    ///
    /// アンビエントは `enableShadows()` の影の中でも減衰しません（影が掛かるのは
    /// 直接光の diffuse / specular のみ）。影の中のディテールはこの値で決まります。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はライティングの影響を受けません。ADR-0005）。
    ///
    /// - Parameter strength: アンビエントライトの強度（`colorMode` のレンジ基準）。
    ///
    /// ### 実行結果
    ///
    /// アンビエントは向きを持たないので、単独では陰影が付かず色が一様に持ち上がるだけです
    /// （左）。立体に見せるには方向を持つ灯と組み合わせます（右）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![ambientLight(_:) の実行結果](https://i.gyazo.com/2e655165dc3a1d94aa012eaae135a24e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///       ambientLight(90)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       directionalLight(-0.5, 1, -0.8)
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func ambientLight(_ strength: Float) {
        context.ambientLight(strength)
    }

    /// RGB 値でアンビエントライトの色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        context.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// シャドウマッピングを有効にします。
    ///
    /// - Note: **3D のみ**に作用します（影が落ちるのは 3D シェイプだけです。ADR-0005）。
    ///
    /// - Parameter resolution: シャドウマップの解像度（ピクセル単位）。
    public func enableShadows(resolution: Int = 2048) {
        context.enableShadows(resolution: resolution)
    }

    /// シャドウマッピングを無効にします。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    public func disableShadows() {
        context.disableShadows()
    }

    /// シャドウアクネを軽減するためのシャドウデプスバイアスを設定します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter value: バイアス値。
    public func shadowBias(_ value: Float) {
        context.shadowBias(value)
    }

    // MARK: 3D Material

    /// スペキュラーハイライトの色を設定します。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はマテリアルの影響を受けません。ADR-0005）。
    ///
    /// - Parameter color: スペキュラー色。
    public func specular(_ color: Color) {
        context.specular(color)
    }

    /// チャンネル値でスペキュラーハイライトの色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はマテリアルの影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    ///
    /// ### 実行結果
    ///
    /// 同じ暗い ``fill(_:_:_:_:)`` に、赤・緑・青のハイライトを載せた 3 つ。
    /// 拡散色と違い、ハイライトの色だけが変わります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![specular(_:_:_:) の実行結果](https://i.gyazo.com/57ad27360e44b22561d478fcaeb42c4f.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(75, 82, 105)
    ///       shininess(28)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           specular(
    ///               i == 0 ? 255 : 70,
    ///               i == 1 ? 255 : 70,
    ///               i == 2 ? 255 : 70
    ///           )
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func specular(_ v1: Float, _ v2: Float, _ v3: Float) {
        context.specular(v1, v2, v3)
    }

    /// グレースケール値でスペキュラーハイライトの色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func specular(_ gray: Float) {
        context.specular(gray)
    }

    /// スペキュラーの光沢度指数を設定します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter value: 光沢度（値が大きいほどハイライトが小さくなります）。
    ///
    /// ### 実行結果
    ///
    /// 左から 4 / 44 / 84。値が大きいほどハイライトが小さく鋭くなります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![shininess(_:) の実行結果](https://i.gyazo.com/bea51a3d3dd331ebe38a1c640df52995.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(70, 100, 170)
    ///       specular(255)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           shininess(4 + Float(i) * 40)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func shininess(_ value: Float) {
        context.shininess(value)
    }

    /// エミッシブ（自己発光）色を設定します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) {
        context.emissive(color)
    }

    /// チャンネル値でエミッシブ色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Note: **3D のみ**に作用します（2D の描画はマテリアルの影響を受けません。ADR-0005）。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    public func emissive(_ v1: Float, _ v2: Float, _ v3: Float) {
        context.emissive(v1, v2, v3)
    }

    /// グレースケール値でエミッシブ色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter gray: グレースケールの明るさ。
    public func emissive(_ gray: Float) {
        context.emissive(gray)
    }

    /// マテリアルのメタリック係数を設定します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter value: メタリック値（0 = 誘電体、1 = 金属）。
    ///
    /// ### 実行結果
    ///
    /// 左から 0 / 0.5 / 1.0。金属に寄るほど拡散色が失われ、灯の映り込みだけで
    /// 形が見えるようになります。PBR は既定リグでは暗いので、`intensity` を上げた
    /// 灯を自分で置いています。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![metallic(_:) の実行結果](https://i.gyazo.com/11783e6a751c5ff69bc3ca34b12138c6.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       pbr(true)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///       roughness(0.25)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           metallic(Float(i) * 0.5)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func metallic(_ value: Float) {
        context.metallic(value)
    }

    /// PBR ラフネスを設定します（自動的に PBR モードに切り替わります）。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter value: ラフネス値（0 = 滑らか、1 = 粗い）。
    ///
    /// ### 実行結果
    ///
    /// 金属（`metallic(1)`）のまま左から 0.1 / 0.45 / 0.8。粗いほどハイライトが
    /// 広く鈍くなり、磨いた金属からつや消しへ移ります。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![roughness(_:) の実行結果](https://i.gyazo.com/3319317fd51bee92127acc9719282fbe.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       pbr(true)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///       metallic(1)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               90 + Float(i) * 150,
    ///               height / 2, 0
    ///           )
    ///           roughness(0.1 + Float(i) * 0.35)
    ///           sphere(65)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func roughness(_ value: Float) {
        context.roughness(value)
    }

    /// PBR アンビエントオクルージョン係数を設定します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter value: アンビエントオクルージョン値（0 = 完全に遮蔽、1 = 遮蔽なし）。
    public func ambientOcclusion(_ value: Float) {
        context.ambientOcclusion(value)
    }

    // MARK: 3D Tone Mapping

    /// 3D のライティング結果に適用するトーンマッピングを設定します。
    ///
    /// レンダーターゲットは LDR（8bit）なので、ライティング結果が 1.0 を超えると
    /// そのままではクランプされ、ハイライトが白く潰れます。トーンマッピングは
    /// 高輝度側を滑らかに丸めて階調を残します。
    ///
    /// ```swift
    /// toneMapping(.acesFilmic)
    /// metallic(0.9)
    /// roughness(0.25)
    /// sphere(80)
    /// ```
    ///
    /// 既定は ``ToneMapMode/none`` です（既存のスケッチの絵が変わらないようにするため）。
    /// **金属や強い光源を使うなら ``ToneMapMode/acesFilmic`` を明示してください。**
    ///
    /// - Note: 掛かるのは **3D のライティング結果だけ**です。2D の描画の色は変わりません
    ///   （3D の陰影は物理量、2D の色は最終色、という非対称を意図的に採っています）。
    ///   ライトが 1 つも無いときの描画（無照明パス）にも掛かりません。
    ///
    /// - Note: `pushStyle()` / `popStyle()` では**巻き戻りません**。画面全体の性質として
    ///   扱われます。
    ///
    /// - Parameter mode: トーンマッピングの方法。
    public func toneMapping(_ mode: ToneMapMode) {
        context.toneMapping(mode)
    }

    /// トーンマッピング前に掛ける露出倍率を設定します。
    ///
    /// 露出は ``toneMapping(_:)`` のモードに関わらず掛かります。既定値の 1.0 は
    /// 恒等倍なので、何も設定しなければ絵は変わりません。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。`pushStyle()` / `popStyle()` では
    ///   巻き戻りません。
    ///
    /// - Parameter value: 露出倍率（既定 1.0。大きいほど明るい）。
    public func exposure(_ value: Float) {
        context.exposure(value)
    }

    // MARK: 3D Environment (IBL / skybox)

    /// 環境（IBL と背景の skybox）を設定します。
    ///
    /// PBR では `metallic` を上げるほど拡散反射が消えます（物理的に正しい挙動）。
    /// 消えた分を埋めるのは**周囲の環境からの反射**なので、環境が無い状態で
    /// `metallic` を上げると、金属ではなく特徴のない灰色の塊になります。
    /// `environment()` はその環境を与えるので、これを呼んで初めて
    /// `metallic` / `roughness` が意図どおりの質感になります。
    ///
    /// ```swift
    /// func setup() {
    ///     environment(.studio)   // これだけで IBL + 背景が入る
    /// }
    ///
    /// func draw() {
    ///     background(0)
    ///     directionalLight(-0.4, -0.6, -1, intensity: 2)
    ///     translate(width / 2, height / 2, 0)
    ///     metallic(0.9)
    ///     roughness(0.25)
    ///     sphere(120)
    /// }
    /// ```
    ///
    /// プリセットはすべて手続き的に生成されるので、HDR 画像などのアセットは要りません。
    /// 焼き上げ（キューブマップの生成と畳み込み）はプリセットにつき 1 回だけ走り、
    /// 以降のフレームのコストはサンプリングだけです。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。`pushStyle()` / `popStyle()` では
    ///   巻き戻りません。画面全体の性質として扱われます。
    ///
    /// - Note: IBL が掛かるのは **PBR 経路だけ**です（``roughness(_:)`` を呼ぶか
    ///   ``pbr(_:)`` を有効にしたとき）。Blinn-Phong の絵は変わりません。
    ///
    /// - Note: トーンマッピングが未指定なら ``ToneMapMode/acesFilmic`` へ自動的に
    ///   昇格します（環境を入れると輝度が 1.0 を超えるため）。``toneMapping(_:)`` を
    ///   明示していれば、そちらが優先されます。
    ///
    /// - Note: `background: true` のとき、skybox は**最初の 3D 描画の直前**に
    ///   1 回だけ描かれます。したがって、それより前に描いた 2D は skybox に覆われ、
    ///   後に描いた 2D（HUD などの前景）は上に残ります。3D を 1 つも描かない
    ///   フレームでは skybox も描かれません。
    ///
    /// - Note: ``ambientLight(_:)`` を明示していない場合、既定のアンビエントは
    ///   0 になります（IBL の拡散項と二重に足さないため）。
    ///
    /// - Parameters:
    ///   - preset: 環境プリセット。
    ///   - intensity: 環境の強度（既定 1.0）。0 以下で無効になります。
    ///   - background: `true`（既定）なら背景としても描きます。IBL だけ欲しいときは
    ///     `false` を渡してください。
    public func environment(
        _ preset: EnvironmentPreset,
        intensity: Float = 1.0,
        background: Bool = true
    ) {
        context.environment(preset, intensity: intensity, background: background)
    }

    /// 環境（IBL と skybox）を無効化します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    public func noEnvironment() {
        context.noEnvironment()
    }

    /// PBR レンダリングモードを明示的に切り替えます。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter enabled: PBR レンダリングを有効にするかどうか。
    ///
    /// ### 実行結果
    ///
    /// 同じ灯・同じ ``fill(_:_:_:_:)`` で、左が既定の Blinn-Phong、右が PBR
    /// （``metallic(_:)`` と ``roughness(_:)`` 付き）。PBR の直接光は `albedo / π` で
    /// 沈むので、同じリグでは暗くなります（``lights()`` の説明を参照）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![pbr(_:) の実行結果](https://i.gyazo.com/8f4a9111a6510b0a7238c4ca69cefba9.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       noStroke()
    ///       ambientLight(55)
    ///       directionalLight(
    ///           -0.4, 1, -0.6,
    ///           intensity: 3
    ///       )
    ///       fill(225, 190, 90)
    ///
    ///       push()
    ///       translate(140, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///
    ///       pbr(true)
    ///       metallic(0.9)
    ///       roughness(0.3)
    ///       push()
    ///       translate(340, height / 2, 0)
    ///       sphere(90)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func pbr(_ enabled: Bool) {
        context.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// MSL ソースコードからカスタムシェーダーマテリアルを作成します。
    ///
    /// ``BuiltinShaders/canvas3DPreamble``（stdlib + 3D 用の構造体定義 + ライティング関数）を
    /// **必ず**先頭へ足すので、フラグメント関数だけを書けば動きます。`Canvas3DUniforms` /
    /// `Canvas3DVertexOut` などは自分で定義しないでください（#713）。
    ///
    /// ```swift
    /// let mat = try createMaterial(source: """
    /// fragment float4 myFragment(Canvas3DVertexOut in [[stage_in]],
    ///                            constant Canvas3DUniforms &u [[buffer(1)]]) {
    ///     return float4(abs(normalize(in.normal)), 1.0);
    /// }
    /// """, fragmentFunction: "myFragment")
    /// material(mat)
    /// box(100)
    /// noMaterial()
    /// ```
    ///
    /// - Note: 作成されるマテリアルは **3D のみ**に適用されます。2D にカスタムシェーダーを
    ///   掛けるには ``loadShader(_:fragment:)`` / ``shader(_:)`` を使用してください
    ///   （ADR-0005）。
    ///
    /// - Parameters:
    ///   - source: Metal Shading Language のソースコード。
    ///   - fragmentFunction: フラグメント関数の名前。
    ///   - vertexFunction: カスタム頂点関数の名前（オプション）。
    /// - Returns: 新しい ``CustomMaterial`` インスタンス。
    /// - Throws: ``MetaphorError``。MSL のコンパイルに失敗した場合は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、指定した
    ///   関数が見つからない場合は ``MetaphorError/material(_:)`` の
    ///   ``MetaphorError/MaterialFailure/shaderNotFound(_:)``。
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try context.createMaterial(source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// カスタムマテリアルを以降の 3D 描画に適用します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    ///
    /// - Parameter customMaterial: 適用するカスタムマテリアル。
    public func material(_ customMaterial: CustomMaterial) {
        context.material(customMaterial)
    }

    /// アクティブなカスタムマテリアルを解除しデフォルトシェーディングに戻します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    public func noMaterial() {
        context.noMaterial()
    }

    // MARK: 3D Texture

    /// 以降の 3D シェイプのテクスチャを設定します。
    ///
    /// - Note: **3D のみ**に作用します（2D で画像を描くには `image()` を
    ///   使用してください。ADR-0005）。
    ///
    /// - Parameter img: テクスチャ画像。
    public func texture(_ img: MImage) {
        context.texture(img)
    }

    /// アクティブなテクスチャを解除します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005）。
    public func noTexture() {
        context.noTexture()
    }

    // MARK: 3D Transform Stack

    /// 現在の変換行列（2D と 3D の両方）をスタックに保存します。
    ///
    /// - Note: **2D と 3D の両方**に作用します。``push()`` との違いは作用先ではなく
    ///   「スタイルを含むかどうか」で、こちらは変換のみを保存します。
    public func pushMatrix() {
        context.pushMatrix()
    }

    /// 最後に保存された変換行列（2D と 3D の両方）をスタックから復元します。
    ///
    /// - Note: **2D と 3D の両方**に作用します（``pushMatrix()`` と対）。
    public func popMatrix() {
        context.popMatrix()
    }

    /// 現在の変換に 3D 平行移動を適用します。
    ///
    /// - Note: **3D のみ**に作用します。2 引数の ``translate(_:_:)`` は 2D と 3D の
    ///   両方に作用します（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameters:
    ///   - x: x 軸方向の移動量。
    ///   - y: y 軸方向の移動量。
    ///   - z: z 軸方向の移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        context.translate(x, y, z)
    }

    /// x 軸周りの回転を適用します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    ///
    /// ### 実行結果
    ///
    /// 左から順に 0 / 0.5 / 1.0 ラジアン。x 軸（画面の横方向）を軸に、上端が奥へ倒れます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotateX(_:) の実行結果](https://i.gyazo.com/b0b8e39439a4f019fce20cc0b3d9b242.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///
    ///       for i in 0..<3 {
    ///           push()
    ///           translate(
    ///               110 + Float(i) * 130,
    ///               height / 2, 0
    ///           )
    ///           rotateX(Float(i) * 0.5)
    ///           box(95)
    ///           pop()
    ///       }
    ///       ```
    ///    }
    /// }
    public func rotateX(_ angle: Float) {
        context.rotateX(angle)
    }

    /// y 軸周りの回転を適用します。
    ///
    /// - Note: **3D のみ**に作用します（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    ///
    /// ### 実行結果
    ///
    /// `frameCount` を角度に使うと、y 軸（画面の縦方向）を軸に回り続けます。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![rotateY(_:) の実行結果（動き）](https://i.gyazo.com/c3943175afcd9b9dbe6774544cce3d6d.gif)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateY(Float(frameCount) * 0.0873)
    ///       rotateX(-0.3)
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func rotateY(_ angle: Float) {
        context.rotateY(angle)
    }

    /// z 軸周りの回転を適用します。
    ///
    /// - Note: **3D のみ**に作用します。1 引数の ``rotate(_:)`` は 2D と 3D の両方に
    ///   作用し、3D 側は本メソッドと同じ z 軸まわりの回転になります
    ///   （ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateZ(_ angle: Float) {
        context.rotateZ(angle)
    }

    /// 現在の変換に非均一 3D スケールを適用します。
    ///
    /// - Note: **3D のみ**に作用します。2 引数の ``scale(_:_:)`` は 2D と 3D の
    ///   両方に作用します（ADR-0005 Amendment 2026-08-02）。
    ///
    /// - Parameters:
    ///   - x: x 軸方向のスケール係数。
    ///   - y: y 軸方向のスケール係数。
    ///   - z: z 軸方向のスケール係数。
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        context.scale(x, y, z)
    }

    // MARK: 3D Shapes

    /// 指定したサイズのボックスを描画します。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        context.box(width, height, depth)
    }

    /// 辺の長さが等しいキューブを描画します。
    ///
    /// - Parameter size: 辺の長さ。
    ///
    /// ### 実行結果
    ///
    /// 既定カメラの原点はキャンバス左上なので、``translate(_:_:_:)`` で中央へ寄せます。
    /// 正対させると正方形にしか見えないため、2 軸で傾けています。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![box(_:) の実行結果](https://i.gyazo.com/0628f02a4dc47cb59470fef39ebbb2ee.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 190, 60)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateY(0.6)
    ///       rotateX(-0.35)
    ///       box(150)
    ///       ```
    ///    }
    /// }
    public func box(_ size: Float) {
        context.box(size)
    }

    /// 球を描画します。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: メッシュテッセレーションの分割数。
    ///
    /// ### 実行結果
    ///
    /// `detail` は球をどれだけ細かく分割するかで、小さくすると多面体になります
    /// （左が `detail: 5`、右が既定の 24）。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![sphere(_:detail:) の実行結果](https://i.gyazo.com/8c6edd1a90dba05c05819b18ef94be4d.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(120, 200, 255)
    ///
    ///       push()
    ///       translate(130, height / 2, 0)
    ///       sphere(80, detail: 5)
    ///       pop()
    ///
    ///       push()
    ///       translate(350, height / 2, 0)
    ///       sphere(80)
    ///       pop()
    ///       ```
    ///    }
    /// }
    public func sphere(_ radius: Float, detail: Int = 24) {
        context.sphere(radius, detail: detail)
    }

    /// 平面を描画します。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    ///
    /// ### 実行結果
    ///
    /// 正対させると ``rect(_:_:_:_:)`` と見分けが付かないので、``rotateX(_:)`` で
    /// 寝かせて奥行きを出しています。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![plane(_:_:) の実行結果](https://i.gyazo.com/2e0a8660fec506bbd00c282c843ab94e.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(150, 220, 120)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-1.1)
    ///       plane(280, 220)
    ///       ```
    ///    }
    /// }
    public func plane(_ width: Float, _ height: Float) {
        context.plane(width, height)
    }

    /// 円柱を描画します。
    ///
    /// 既定カメラはピクセル空間（ワールド 1 単位 = 1 ピクセル）なので、`radius` /
    /// `height` はピクセル相当の大きさで指定します。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 円周方向の分割数。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![cylinder(radius:height:detail:) の実行結果](https://i.gyazo.com/47680338f40c5454225003010160b2a1.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 150, 120)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.45)
    ///       cylinder(radius: 80, height: 190)
    ///       ```
    ///    }
    /// }
    public func cylinder(radius: Float, height: Float, detail: Int = 24) {
        context.cylinder(radius: radius, height: height, detail: detail)
    }

    /// 円錐を描画します。
    ///
    /// 既定カメラはピクセル空間（ワールド 1 単位 = 1 ピクセル）なので、`radius` /
    /// `height` はピクセル相当の大きさで指定します。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 円周方向の分割数。
    ///
    /// ### 実行結果
    ///
    /// y 軸は画面下向きなので、そのまま描くと**頂点が下**を向きます。上向きの円錐に
    /// するには ``rotateZ(_:)`` で半回転させてください。
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![cone(radius:height:detail:) の実行結果](https://i.gyazo.com/26fccf002e09c5699fcf42b9935b6379.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(255, 205, 90)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.45)
    ///       cone(radius: 95, height: 200)
    ///       ```
    ///    }
    /// }
    public func cone(radius: Float, height: Float, detail: Int = 24) {
        context.cone(radius: radius, height: height, detail: detail)
    }

    /// トーラス（ドーナツ形状）を描画します。
    ///
    /// 既定カメラはピクセル空間（ワールド 1 単位 = 1 ピクセル）なので、`ringRadius` /
    /// `tubeRadius` はピクセル相当の大きさで指定します。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブの中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: 分割数。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 1) {
    ///       ![torus(ringRadius:tubeRadius:detail:) の実行結果](https://i.gyazo.com/6238ad4f021c6d0294b39d844d9796f0.png)
    ///    }
    ///    @Column(size: 2) {
    ///       ```swift
    ///       background(18)
    ///       lights()
    ///       noStroke()
    ///       fill(200, 140, 255)
    ///       translate(width / 2, height / 2, 0)
    ///       rotateX(-0.95)
    ///       torus(
    ///           ringRadius: 110,
    ///           tubeRadius: 40
    ///       )
    ///       ```
    ///    }
    /// }
    public func torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24) {
        context.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// ビルド済みメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するメッシュ。
    public func mesh(_ mesh: Mesh) {
        context.mesh(mesh)
    }

    /// 同一メッシュを複数のトランスフォームで一括描画します（明示インスタンシング）。
    ///
    /// 各インスタンスは「現在の変換行列 × `transforms[i]`」で描かれます。次のループと同値ですが、
    /// 状態評価が 1 回で済むぶん CPU 側が軽くなります。
    ///
    /// ```swift
    /// for t in transforms {
    ///     pushMatrix(); applyMatrix(t); mesh(m); popMatrix()
    /// }
    /// ```
    ///
    /// fill / stroke / material / texture / ライトはインスタンス間で共有されます
    /// （インスタンスごとに変えられるのは ``drawInstanced(_:transforms:colors:)`` の fill 色のみ）。
    ///
    /// - Parameters:
    ///   - mesh: 描画するメッシュ。
    ///   - transforms: インスタンスごとのローカル変換。空配列なら何も描きません。
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4]) {
        context.drawInstanced(mesh, transforms: transforms)
    }

    /// 同一メッシュを、インスタンスごとの fill 色つきで一括描画します。
    ///
    /// - Parameters:
    ///   - mesh: 描画するメッシュ。
    ///   - transforms: インスタンスごとのローカル変換。空配列なら何も描きません。
    ///   - colors: インスタンスごとの fill 色。`transforms` より短いときは不足分に現在の
    ///     fill 色を使い、長いときは余りを無視します。stroke 色とマテリアルは共通のままです。
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4], colors: [Color]) {
        context.drawInstanced(mesh, transforms: transforms, colors: colors)
    }

    /// ダイナミックメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するダイナミックメッシュ。
    public func dynamicMesh(_ mesh: DynamicMesh) {
        context.dynamicMesh(mesh)
    }

    /// 新しい空のダイナミックメッシュを作成します。
    ///
    /// - Returns: 新しい ``DynamicMesh`` インスタンス。
    public func createDynamicMesh() -> DynamicMesh {
        context.createDynamicMesh()
    }

    // MARK: - プリミティブメッシュの生成

    /// ボックスのメッシュを生成します（描画はしません）。
    ///
    /// ``box(_:_:_:)`` が「描く」のに対し、こちらは ``Mesh`` を**値として**返します。
    /// ``mesh(_:)`` や ``drawInstanced(_:transforms:)`` に渡すためのものです。
    ///
    /// ```swift
    /// func setup() {
    ///     cube = createBoxMesh(12)
    /// }
    /// func draw() {
    ///     drawInstanced(cube, transforms: transforms)
    /// }
    /// ```
    ///
    /// 同じ引数の再呼び出しは同一インスタンスを返します（``loadModel(_:normalize:cache:)``
    /// と同じ挙動）。寸法を毎フレーム変えて呼ぶとメッシュを作り直し続けるため、生成は
    /// `setup()` で行い、大きさの変化は ``scale(_:)`` や `transforms` 側で表現してください。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createBoxMesh(_ width: Float, _ height: Float, _ depth: Float) -> Mesh? {
        context.createBoxMesh(width, height, depth)
    }

    /// 同じ寸法の立方体メッシュを生成します（描画はしません）。
    ///
    /// - Parameter size: 立方体の辺の長さ。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createBoxMesh(_ size: Float) -> Mesh? {
        context.createBoxMesh(size)
    }

    /// 球のメッシュを生成します（描画はしません）。
    ///
    /// `detail` の解釈は ``sphere(_:detail:)`` と同じで、同じ引数なら同じジオメトリになります。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: 分割数（デフォルトは 24）。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createSphereMesh(_ radius: Float, detail: Int = 24) -> Mesh? {
        context.createSphereMesh(radius, detail: detail)
    }

    /// 平面のメッシュを生成します（描画はしません）。
    ///
    /// XY 平面上の矩形で、法線は +Z 方向です。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createPlaneMesh(_ width: Float, _ height: Float) -> Mesh? {
        context.createPlaneMesh(width, height)
    }

    /// 円柱のメッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 分割数（デフォルトは 24）。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createCylinderMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        context.createCylinderMesh(radius: radius, height: height, detail: detail)
    }

    /// 円錐のメッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 分割数（デフォルトは 24）。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createConeMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        context.createConeMesh(radius: radius, height: height, detail: detail)
    }

    /// トーラスのメッシュを生成します（描画はしません）。
    ///
    /// `detail` の解釈は ``torus(ringRadius:tubeRadius:detail:)`` と同じで、
    /// 同じ引数なら同じジオメトリになります。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブの中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: 分割数（デフォルトは 24）。
    /// - Returns: 生成されたメッシュ。GPU バッファを確保できなかった場合は `nil`。
    public func createTorusMesh(ringRadius: Float, tubeRadius: Float, detail: Int = 24) -> Mesh? {
        context.createTorusMesh(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// ファイルから 3D モデルを読み込みます（OBJ、USDZ、ABC）。
    ///
    /// 既定でパスキーのキャッシュが効き、同じパス・同じ `normalize` の再読込は
    /// 同一の ``Mesh`` インスタンスを返します。
    ///
    /// - Parameters:
    ///   - path: モデルのファイルパス。
    ///   - normalize: バウンディングボックスを正規化するかどうか（デフォルトは `true`）。
    ///     正規化すると原点中心・**最大辺が 2 単位**（[-1, 1]）になるので、ピクセル座標系の
    ///     キャンバスへそのまま描くと数ピクセルの大きさにしかなりません。``scale(_:)`` で
    ///     大きさを与えてください。モデルの座標をそのまま使うなら `false` を渡します。
    ///   - cache: キャッシュを使うか（既定 true。`false` で独立したコピーを読み込み）。
    /// - Returns: 読み込まれたメッシュ。読み込みに失敗した場合は `nil`。
    public func loadModel(_ path: String, normalize: Bool = true, cache: Bool = true) -> Mesh? {
        context.loadModel(path, normalize: normalize, cache: cache)
    }

    /// 3D モデルを非同期で読み込みます（パース処理をメインスレッド外で実行）。
    ///
    /// - Parameters:
    ///   - path: モデルのファイルパス。
    ///   - normalize: バウンディングボックスを正規化するかどうか（デフォルトは `true`）。
    ///     正規化すると原点中心・**最大辺が 2 単位**（[-1, 1]）になるので、ピクセル座標系の
    ///     キャンバスへそのまま描くと数ピクセルの大きさにしかなりません。``scale(_:)`` で
    ///     大きさを与えてください。モデルの座標をそのまま使うなら `false` を渡します。
    ///   - cache: キャッシュを使うか（既定 true。同一インスタンスが返ります）。
    /// - Returns: 読み込まれたメッシュ。
    /// - Throws: モデルを解析できない場合（メッシュ・頂点位置が無い、空メッシュなど）は
    ///   ``MetaphorError/mesh(_:)`` の ``MetaphorError/MeshFailure/parseError(_:)``、
    ///   GPU バッファを確保できない場合は ``MetaphorError/bufferCreationFailed(size:)``。
    public func loadModelAsync(
        _ path: String, normalize: Bool = true, cache: Bool = true
    ) async throws -> Mesh {
        try await context.loadModelAsync(path, normalize: normalize, cache: cache)
    }
}
