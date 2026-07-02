import Metal

// MARK: - Canvas-Level Pixel Access

extension SketchContext {

    /// 直接ピクセル操作用のピクセルバッファ（遅延生成）。
    private static var _pixelBufferKey: UInt8 = 0

    /// ピクセルバッファにアクセスし、必要に応じて作成します。
    var pixelBuffer: PixelBuffer? {
        get {
            objc_getAssociatedObject(self, &Self._pixelBufferKey) as? PixelBuffer
        }
        set {
            objc_setAssociatedObject(self, &Self._pixelBufferKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// キャンバスの内容を CPU の ``pixels`` 配列へ読み戻します（Processing 互換、#202）。
    ///
    /// 初回呼び出し時またはキャンバスサイズ変更時にピクセルバッファを作成し、
    /// キャンバスのカラーテクスチャの内容を読み戻します。
    ///
    /// - Important: 読み戻せるのは**前フレーム末尾までに確定した内容**です。
    ///   現在のフレームで既に発行した描画コマンド（この draw() 内の先行呼び出し）は
    ///   まだ GPU にコミットされていないため含まれません。Processing の典型パターン
    ///   （draw() の先頭で `loadPixels()` → 加工 → `updatePixels()`）では、
    ///   前フレームの最終内容 = 現在のキャンバス内容なので期待どおりに動作します。
    ///
    /// - Note: GPU の完了を待つためメインスレッドをブロックします（Processing と同等）。
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)

        if pixelBuffer == nil || pixelBuffer!.width != w || pixelBuffer!.height != h {
            pixelBuffer = PixelBuffer(width: w, height: h, device: renderer.device)
        }
        guard let pb = pixelBuffer else { return }

        // レンダラーと同じキューで blit することで、コミット済みフレームとの
        // 順序が保証される（描画中フレームは未コミットのため含まれない）
        pb.download(
            from: renderer.textureManager.colorTexture,
            commandQueue: renderer.commandQueue
        )
    }

    /// ピクセルバッファを GPU にアップロードしフルスクリーンクワッドとして描画します。
    ///
    /// `pixels` バッファの変更後にこれを呼び出して変更を表示してください。
    public func updatePixels() {
        guard let pb = pixelBuffer else { return }
        pb.upload()
        canvas.drawTexturedQuad(texture: pb.texture, x: 0, y: 0, w: width, h: height)
    }
}
