// MARK: - Pixel Manipulation

extension Sketch {

    /// キャンバスのピクセルデータへの直接アクセス（パック済み UInt32 値）。
    ///
    /// 各要素は BGRA パックカラー: `(A << 24) | (R << 16) | (G << 8) | B`。
    /// パック値の作成には `color()` を使用します。`pixels[y * Int(width) + x]` でインデックスアクセスします。
    ///
    /// アクセス前に ``loadPixels()``、書き込み後に ``updatePixels()`` を呼び出してください。
    ///
    /// 色は **straight alpha**（`fill()` や `color()` と同じ、α を掛ける前の値）です。
    /// 半透明の画素を読んでも色が沈まず、読んだ値をそのまま書き戻せば絵は変わりません
    /// （ADR-0012 / #848）。
    ///
    /// - Note: 読み取り系なので**決してクラッシュしません**（ADR-0005 / #356）。
    ///   ``loadPixels()`` 前でも、SketchRunner が context を用意する前（`init` や
    ///   プロパティ初期化子）でも、teardown 後でも空バッファを返します。描画 API と
    ///   違い ``Sketch/context`` を経由しないのはこのためです。
    public var pixels: UnsafeMutableBufferPointer<UInt32> {
        guard let pb = _context?.pixelBuffer else {
            return UnsafeMutableBufferPointer(start: nil, count: 0)
        }
        return pb.pixels
    }

    /// **呼び出し時点の**キャンバス内容を ``pixels`` 配列へ読み戻します（Processing 互換）。
    ///
    /// 呼び出し後、``pixels`` を読み書きし、``updatePixels()`` で反映してください。
    /// `draw()` の途中で呼べば、それまでに発行した描画（`background()` や図形、
    /// `image()`）が反映された状態が読めます。
    ///
    /// ```swift
    /// func draw() {
    ///     background(0)
    ///     fill(255, 0, 0)
    ///     circle(width / 2, height / 2, 100)
    ///     loadPixels()                 // ここまでの描画（円まで）が読める
    ///     for i in 0..<pixels.count { pixels[i] ^= 0x00FF_FFFF }  // 色を反転
    ///     updatePixels()
    /// }
    /// ```
    ///
    /// - Important: 同一フレームの読み戻しは**影オフの通常経路**で有効です。影を有効に
    ///   している場合（`enableShadows()`）は `draw()` が記録パスとして先に実行される
    ///   ため分割できず、**直近にコミット済みのフレーム内容**が読めます（初回のみ警告）。
    ///   `draw()` の外（`setup()` やフレーム間）で呼んだ場合も同じです。
    ///
    /// - Note: GPU の完了を待つためメインスレッドをブロックします（Processing と同等）。
    ///   `loadPixels()` を呼ばないスケッチには一切コストがかかりません。
    ///
    /// - Note: 読み戻しのために内部でレンダーパスを分割するため、`loadPixels()` を
    ///   またいだ 3D 同士は深度比較されません（継続パスでデプスがクリアされます）。
    ///
    /// - Note: `loadPixels()` は 2D バッチの確定点でもあります。影オフの即時経路では
    ///   重ね順が呼び出し順ではなく**エンコード順**で決まるため、`loadPixels()` より
    ///   **前**に描いた 2D は、**後**に描いた 3D の背後へ回ります。3D の手前に置きたい
    ///   2D は `loadPixels()` の後に描いてください（#832。契機の一覧は
    ///   [ADR-0003](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0003-unified-command-stream.md)
    ///   の 2026-08-16 追記）。`loadPixels()` の前後それぞれの中では、フレーム末尾と
    ///   同じく 2D が 3D の手前に出ます。
    public func loadPixels() {
        context.loadPixels()
    }

    /// 変更されたピクセルデータをアップロードしキャンバスに描画します。
    ///
    /// ピクセルバッファを GPU テクスチャに転送し、フルスクリーンクワッドとして
    /// レンダリングします。``pixels`` への書き込み後にこれを呼び出してください。
    ///
    /// - Note: ``loadPixels()`` を一度も呼んでいない場合は何もしません。
    public func updatePixels() {
        context.updatePixels()
    }

    /// 1 画素の色を読みます（Processing の `get(x, y)` 互換）。
    ///
    /// ``pixels`` のパック値をほどく手間を省くための入口で、実体は同じバッファを読みます。
    ///
    /// ```swift
    /// func draw() {
    ///     background(0)
    ///     fill(255, 0, 0)
    ///     circle(width / 2, height / 2, 100)
    ///     loadPixels()                                  // ← 先に読み戻す
    ///     let c = get(Int(width) / 2, Int(height) / 2)  // 円の中心の赤
    ///     print(c)
    /// }
    /// ```
    ///
    /// - Important: **暗黙の読み戻しはしません。** ``loadPixels()`` を先に呼んでください
    ///   （呼んでいなければ黒を返し、初回だけ警告します）。Processing の `get()` は
    ///   単に遅いだけですが、metaphor の読み戻しは GPU 待ちに加えて**レンダーパスの分割**
    ///   を伴い、深度クリアと 2D/3D の重ね順を通じて**絵そのものを変えます**
    ///   （``loadPixels()`` の Note 群）。1 画素を読むたびにそれが起きないよう、
    ///   読み戻しは明示的な ``loadPixels()`` だけに限っています。
    ///
    /// - Important: 影を有効にしている場合（`enableShadows()`）は ``loadPixels()`` が
    ///   同一フレームを読み戻せず、**直近にコミット済みのフレーム内容**が読めます。
    ///   `get()` はその結果を読むので、同じ制約がそのまま乗ります。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。
    ///   - y: 垂直方向のピクセル座標。
    /// - Returns: straight alpha の ``Color``（`fill()` に渡したのと同じ値。ADR-0012）。
    ///   範囲外・未 ``loadPixels()`` の場合は黒。
    ///
    /// - Note: 読み取り系なので**決してクラッシュしません**（ADR-0005 / #356）。
    ///   context が用意される前（`init` やプロパティ初期化子）でも黒を返します。
    public func get(_ x: Int, _ y: Int) -> Color {
        guard let ctx = _context else { return .black }
        return ctx.get(x, y)
    }

    /// キャンバスの矩形領域を ``MImage`` として切り出します（Processing の
    /// `get(x, y, w, h)` 互換）。
    ///
    /// 返る画像は**要求した `w` × `h`** です。キャンバスからはみ出した部分は透明
    /// （α = 0）で埋まります（Processing と同じ）。`image()` でそのまま貼れます。
    ///
    /// ```swift
    /// loadPixels()
    /// if let stamp = get(0, 0, 64, 64) {
    ///     image(stamp, 100, 100)
    /// }
    /// ```
    ///
    /// - Important: ``get(_:_:)`` と同じく**暗黙の読み戻しはしません**。影オン時の制約も
    ///   同じです（``loadPixels()`` の `- Important:` を参照）。
    ///
    /// - Parameters:
    ///   - x: 切り出す矩形の左上 X 座標。
    ///   - y: 切り出す矩形の左上 Y 座標。
    ///   - w: 切り出す幅（1 以上）。
    ///   - h: 切り出す高さ（1 以上）。
    /// - Returns: 切り出した ``MImage``。未 ``loadPixels()``・サイズが 0 以下・テクスチャ
    ///   確保に失敗した場合は nil。
    public func get(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MImage? {
        guard let ctx = _context else { return nil }
        return ctx.get(x, y, w, h)
    }

    /// 1 画素の色を書き込みます（Processing の `set(x, y, c)` 互換）。
    ///
    /// ```swift
    /// loadPixels()
    /// set(10, 20, Color(r: 1, g: 0, b: 0))
    /// updatePixels()               // ← これでキャンバスへ出る
    /// ```
    ///
    /// - Important: 書き込み先は CPU 側の ``pixels`` バッファです。キャンバスへ出すには
    ///   ``updatePixels()`` が必要で、Processing の `set()` が即座に反映されるのとは
    ///   異なります。``loadPixels()`` を呼んでいなければ何もしません（初回だけ警告）。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。範囲外は無視されます。
    ///   - y: 垂直方向のピクセル座標。範囲外は無視されます。
    ///   - color: 書き込む色。straight alpha として詰められます（ADR-0012）。
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        context.set(x, y, color)
    }
}
