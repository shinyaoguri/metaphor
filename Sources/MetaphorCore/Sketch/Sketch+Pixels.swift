// MARK: - Pixel Manipulation

extension Sketch {

    /// キャンバスのピクセルデータへの直接アクセス（パック済み UInt32 値）。
    ///
    /// 各要素は BGRA パックカラー: `(A << 24) | (R << 16) | (G << 8) | B`。
    /// パック値の作成には `color()` を使用します。`pixels[y * Int(width) + x]` でインデックスアクセスします。
    ///
    /// アクセス前に ``loadPixels()``、書き込み後に ``updatePixels()`` を呼び出してください。
    public var pixels: UnsafeMutableBufferPointer<UInt32> {
        guard let pb = context.pixelBuffer else {
            return UnsafeMutableBufferPointer(start: nil, count: 0)
        }
        return pb.pixels
    }

    /// ピクセルバッファを直接ピクセル操作用に準備します。
    ///
    /// 初回呼び出し時にバッファを作成します。以降の呼び出しでは既存のバッファを再利用します。
    /// 呼び出し後、``pixels`` に書き込み、``updatePixels()`` を呼び出してください。
    public func loadPixels() {
        context.loadPixels()
    }

    /// 変更されたピクセルデータをアップロードしキャンバスに描画します。
    ///
    /// ピクセルバッファを GPU テクスチャに転送し、フルスクリーンクワッドとして
    /// レンダリングします。``pixels`` への書き込み後にこれを呼び出してください。
    public func updatePixels() {
        context.updatePixels()
    }
}
