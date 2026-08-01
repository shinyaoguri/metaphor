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

    /// キャンバスの内容を CPU の ``pixels`` 配列へ読み戻します（Processing 互換、#202 / #326）。
    ///
    /// `draw()` の途中で呼ばれた場合は、**その時点までの描画を GPU に確定させてから**
    /// 読み戻します（Processing の `loadPixels()` と同じ）。実装としてはメインの
    /// レンダーパスを一度閉じてコマンドバッファをコミットし、完了を待ってから
    /// `loadAction = .load` の継続パスで描画を再開します。カラーは保持されるため、
    /// 読み戻しを挟んでもフレームの見た目は変わりません。
    ///
    /// - Important: 同一フレーム読み戻しが効くのは**影オフの通常経路**です。
    ///   シャドウ同一フレーム化（#70）では `draw()` が「記録パス」として実行され、
    ///   その時点ではまだ何もエンコードされていないため分割できません。この場合と
    ///   `draw()` の外（`setup()` やフレーム間）で呼ばれた場合は、**直近にコミット済みの
    ///   フレーム内容**を読み戻します。
    ///
    /// - Note: GPU の完了を待つためメインスレッドをブロックします（Processing と同等）。
    ///   同一フレーム経路では、そのフレームのトリプルバッファリングによる並列化が
    ///   分割点で一度途切れます。呼ばないスケッチには一切コストがかかりません。
    ///
    /// - Note: 継続パスではデプスがクリアされます。`loadPixels()` をまたいだ 3D 同士は
    ///   深度比較されません（2D は深度テストを使わないため影響なし）。
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)

        if pixelBuffer == nil || pixelBuffer!.width != w || pixelBuffer!.height != h {
            pixelBuffer = PixelBuffer(width: w, height: h, device: renderer.device)
        }
        guard let pb = pixelBuffer else { return }

        let source = renderer.textureManager.colorTexture

        // 同一フレーム経路（Processing 互換）: draw() 実行中でメインパスが分割可能なら、
        // ここまでの描画を確定させてから読み戻す。
        if canvas.currentEncoder != nil, !canvas.isDeferring, renderer.canSplitMainPass {
            // 保留中のバッチを分割前のパスへ出し切る（出し忘れると「ここまでの描画」に
            // 含まれない）。2D の頂点バッチと 3D のインスタンスバッチの両方。
            canvas.flush()
            canvas3D.flushInstanceBatch()

            guard let continuation = renderer.splitMainPassForReadback({ commandBuffer in
                pb.encodeDownload(from: source, into: commandBuffer)
            }) else {
                // 継続パスを作れなかった。renderer 側がフレームを畳むので何もしない。
                return
            }
            pb.finishDownload()
            canvas.rebindEncoder(continuation)
            canvas3D.rebindEncoder(continuation)
            return
        }

        if canvas.isDeferring, !didWarnDeferredPixelReadback {
            didWarnDeferredPixelReadback = true
            metaphorWarning(
                "loadPixels(): same-frame readback is unavailable while shadows are enabled "
                + "(the draw pass is recorded first). Reading the last committed frame instead."
            )
        }

        // フォールバック: 直近にコミット済みのフレーム内容。レンダラーと同じキューで
        // blit することで commit 順序により最新のコミット済み内容が読める。
        pb.download(from: source, commandQueue: renderer.commandQueue)
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
