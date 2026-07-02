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

    /// キャンバスの内容を ``pixels`` 配列へ読み戻します（Processing 互換）。
    ///
    /// 呼び出し後、``pixels`` を読み書きし、``updatePixels()`` で反映してください。
    ///
    /// - Important: 読み戻せるのは**前フレーム末尾までに確定した内容**です
    ///   （この draw() 内の先行描画はまだ含まれません）。draw() の先頭で呼ぶ
    ///   典型パターンでは現在のキャンバス内容と一致します。
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
