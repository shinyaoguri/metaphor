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
    ///   またいだ 3D 同士は深度比較されません（2D は深度テストを使わないため影響なし）。
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
}
