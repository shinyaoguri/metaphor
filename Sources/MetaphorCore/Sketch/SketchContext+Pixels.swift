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

    /// キャンバスの内容を CPU の ``Sketch/pixels`` 配列へ読み戻します（Processing 互換、#202 / #326）。
    ///
    /// `draw()` の途中で呼ばれた場合は、**その時点までの描画を GPU に確定させてから**
    /// 読み戻します（Processing の `loadPixels()` と同じ）。実装としてはメインの
    /// レンダーパスを一度閉じてコマンドバッファをコミットし、完了を待ってから
    /// `loadAction = .load` の継続パスで描画を再開します。カラーは保持され、保留中の
    /// バッチは `endFrame()` と同じ順（3D → 2D。#832）で吐かれるため、読み戻しを
    /// 挟んでもそこまでに描いた絵の見た目は変わりません。
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
    ///   深度比較されません。
    ///
    /// - Note: `loadPixels()` は 2D バッチの確定点でもあります（ADR-0003 の
    ///   「2D バッチがフレーム末尾より前に吐かれる契機」の 6 番目）。即時経路の重ね順は
    ///   エンコード順で決まるため、分割**前**に描いた 2D は分割**後**にエンコードされる
    ///   3D の背後へ回ります。分割の前後それぞれの中では、`endFrame()` と同じく
    ///   2D が 3D の手前に出ます。
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
            //
            // 順序は `endFrame()` と揃える（3D → 2D。#832）。即時経路の重ね順は
            // エンコード順で決まるので、ここだけ 2D → 3D で吐くと分割前に描いた 2D が
            // 3D の背後へ落ち、`loadPixels()` がフレームの見た目を変えてしまう。
            canvas3D.flushInstanceBatch()
            canvas.flush()

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
    ///
    /// `pixels` は straight alpha（ADR-0012 / #848）なので、`straightAlpha: true` で
    /// **割り戻さない**フラグメントを選びます。ここを既定の（premultiplied 前提の）
    /// 経路で描くと、半透明の画素が α を掛けずに合成されて明るく出ます。
    ///
    /// クワッドを `-0.5` から張るのは、2D の投影行列が**半ピクセルずらしている**ため
    /// （`Canvas2D.projectionMatrix`: canvas x=10 → viewport x=10.5。整数座標の
    /// `strokeWeight(1)` を 1 画素にクリスプに乗せるための意図的なオフセット）。
    /// 素直に `x: 0, w: width` で張ると各フラグメントがテクセルの**境目**を
    /// サンプルし、`filter::linear` が隣接 4 テクセルを 25% ずつ混ぜます。
    /// 1 画素だけ書き換えた `set()` はぼやけて 4 画素へ散り、`loadPixels()` →
    /// `updatePixels()` のフィードバックはフレームごとに滲みます。`-0.5` ずらすと
    /// クワッドがピクセルグリッドに揃い、テクセル中心が読まれて 1:1 になります（#812）。
    public func updatePixels() {
        guard let pb = pixelBuffer else { return }
        pb.upload()
        canvas.drawTexturedQuad(
            texture: pb.texture, x: -0.5, y: -0.5, w: width, h: height, straightAlpha: true)
    }
}

// MARK: - Canvas get() / set()（#812）

extension SketchContext {

    /// 直近の ``loadPixels()`` が読み戻した内容から 1 画素の色を返します（#812）。
    ///
    /// **暗黙の読み戻しは行いません。** ``loadPixels()`` を呼んでいなければ黒を返します
    /// （初回のみ警告）。``updatePixels()`` が未 ``loadPixels()`` で no-op なのと同じ流儀です。
    ///
    /// Processing の `get(x, y)` は未 `loadPixels()` でも読めますが、metaphor の読み戻しは
    /// GPU 待ちに加えて**レンダーパスの分割**を伴います（深度クリア・2D/3D の重ね順が変わる）。
    /// 1 画素の読み取りが絵そのものを変えてしまうため、暗黙には走らせません。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。
    ///   - y: 垂直方向のピクセル座標。
    /// - Returns: straight alpha の ``Color``（ADR-0012）。範囲外・未 ``loadPixels()``
    ///   の場合は黒。
    public func get(_ x: Int, _ y: Int) -> Color {
        guard let pb = pixelBuffer else {
            warnPixelAccessBeforeLoadPixels("get(x, y)")
            return .black
        }
        guard x >= 0, x < pb.width, y >= 0, y < pb.height else { return .black }
        return Self.unpackStraight(pb.pixels[y * pb.width + x])
    }

    /// キャンバスの矩形領域を ``MImage`` として切り出します（Processing の
    /// `get(x, y, w, h)` 互換、#812）。
    ///
    /// 返る画像は**要求した `w` × `h`** です。キャンバスからはみ出した部分は透明
    /// （α = 0）で埋まります（Processing と同じ）。
    ///
    /// ``get(_:_:)`` と同じく暗黙の読み戻しはしません。``loadPixels()`` を先に呼んでください。
    ///
    /// - Parameters:
    ///   - x: 切り出す矩形の左上 X 座標。
    ///   - y: 切り出す矩形の左上 Y 座標。
    ///   - w: 切り出す幅（1 以上）。
    ///   - h: 切り出す高さ（1 以上）。
    /// - Returns: 切り出した ``MImage``。未 ``loadPixels()``・サイズが 0 以下・テクスチャ
    ///   確保に失敗した場合は nil。
    public func get(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MImage? {
        guard w > 0, h > 0 else {
            metaphorWarning("get(x, y, w, h): width and height must be positive (got \(w)x\(h))")
            return nil
        }
        guard let pb = pixelBuffer else {
            warnPixelAccessBeforeLoadPixels("get(x, y, w, h)")
            return nil
        }

        // キャンバスの中身は premultiplied（ADR-0012）。`pixels` は straight なので、
        // MImage のテクスチャへ写すときに掛け直す。MImage.loadPixels() は
        // premultiplied 前提で割り戻すため、straight のまま置くと半透明だけ明るくなる。
        var packed = [UInt32](repeating: 0, count: w * h)
        packed.withUnsafeMutableBufferPointer { out in
            guard let dst = out.baseAddress, let src = pb.pixels.baseAddress else { return }
            for row in 0..<h {
                let sy = y + row
                guard sy >= 0, sy < pb.height else { continue }
                for col in 0..<w {
                    let sx = x + col
                    guard sx >= 0, sx < pb.width else { continue }
                    dst[row * w + col] = Self.premultiplyPacked(src[sy * pb.width + sx])
                }
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let texture = renderer.device.makeTexture(descriptor: desc) else {
            metaphorWarning("get(x, y, w, h): failed to allocate a \(w)x\(h) texture")
            return nil
        }
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: w, height: h, depth: 1))
        packed.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
        }
        return MImage(texture: texture)
    }

    /// 1 画素の色を書き込みます（Processing の `set(x, y, c)` 互換、#812）。
    ///
    /// 書き込み先は CPU 側の ``Sketch/pixels`` バッファなので、キャンバスへ出すには
    /// ``updatePixels()`` が必要です（Processing の `set()` が即時に反映されるのとは違います）。
    /// ``loadPixels()`` を呼んでいなければ何もしません（初回のみ警告）。
    ///
    /// - Parameters:
    ///   - x: 水平方向のピクセル座標。
    ///   - y: 垂直方向のピクセル座標。
    ///   - color: 書き込む色。straight alpha として詰められます（ADR-0012）。
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        guard let pb = pixelBuffer else {
            warnPixelAccessBeforeLoadPixels("set(x, y, c)")
            return
        }
        guard x >= 0, x < pb.width, y >= 0, y < pb.height else { return }
        pb.pixels[y * pb.width + x] = Self.packStraight(color)
    }

    // MARK: - Helpers

    /// ``loadPixels()`` 前の `get()` / `set()` を一度だけ警告します。
    private func warnPixelAccessBeforeLoadPixels(_ api: String) {
        guard !didWarnPixelAccessBeforeLoad else { return }
        didWarnPixelAccessBeforeLoad = true
        metaphorWarning(
            "\(api) requires loadPixels() first — metaphor does not read back the canvas "
            + "implicitly (the readback blocks on the GPU and splits the render pass). "
            + "Call loadPixels() before reading or writing pixels."
        )
    }

    /// BGRA パックの straight な `UInt32` を ``Color`` へ展開します。
    @inline(__always)
    private static func unpackStraight(_ packed: UInt32) -> Color {
        Color(
            r: Float((packed >> 16) & 0xFF) / 255.0,
            g: Float((packed >> 8) & 0xFF) / 255.0,
            b: Float(packed & 0xFF) / 255.0,
            alpha: Float((packed >> 24) & 0xFF) / 255.0
        )
    }

    /// ``Color`` を BGRA パックの straight な `UInt32` へ詰めます（`color(r:g:b:a:)` と同形）。
    @inline(__always)
    private static func packStraight(_ color: Color) -> UInt32 {
        let r = UInt32(max(0, min(255, color.r * 255 + 0.5)))
        let g = UInt32(max(0, min(255, color.g * 255 + 0.5)))
        let b = UInt32(max(0, min(255, color.b * 255 + 0.5)))
        let a = UInt32(max(0, min(255, color.a * 255 + 0.5)))
        return (a << 24) | (r << 16) | (g << 8) | b
    }

    /// straight な BGRA パック値を premultiplied へ掛け直します（四捨五入）。
    @inline(__always)
    private static func premultiplyPacked(_ packed: UInt32) -> UInt32 {
        let a = (packed >> 24) & 0xFF
        if a == 255 { return packed }
        if a == 0 { return 0 }
        let r = (((packed >> 16) & 0xFF) * a + 127) / 255
        let g = (((packed >> 8) & 0xFF) * a + 127) / 255
        let b = ((packed & 0xFF) * a + 127) / 255
        return (a << 24) | (r << 16) | (g << 8) | b
    }
}
