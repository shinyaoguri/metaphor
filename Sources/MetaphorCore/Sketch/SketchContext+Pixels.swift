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

    /// ピクセルバッファが存在しキャンバスサイズと一致することを保証します。
    ///
    /// 初回呼び出し時またはキャンバスサイズが変更された際に新しいピクセルバッファを作成します。
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)

        if let existing = pixelBuffer, existing.width == w, existing.height == h {
            return
        }

        pixelBuffer = PixelBuffer(width: w, height: h, device: renderer.device)
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
