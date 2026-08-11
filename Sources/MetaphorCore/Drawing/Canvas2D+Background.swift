import Metal
import simd

extension Canvas2D {
    // MARK: - 背景

    /// 現在の変換を無視して、キャンバス全体を単色で塗りつぶします。
    ///
    /// このフレームでまだ何も描画されていない場合、最適なパフォーマンスのため
    /// クリアカラーの更新のみを行います。
    ///
    /// - Parameter color: 背景色。
    public func background(_ color: Color) {
        let c = color.simd
        svgRecorder?.recordBackground(c)
        backgroundCalledThisFrame = true
        pendingClearColor = c
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        // シャドウ同一フレーム化の遅延モードでは、フレーム先頭の background() は
        // メインパスの loadAction = .clear が担う（endFrame の setShouldClear が
        // 同フレームで反映される。#70）。ただしフレーム途中（既に 2D/3D を描画済み）の
        // background() をクリアに任せると「rect(); background(); circle()」で先に
        // 描いた図形が残るため、背景クワッドを呼び出し順（seq 付き）で emit する（#152）。
        if isDeferring {
            let drewSomething = hasDrawnAnything || (hasRecorded3D?() ?? false)
            guard drewSomething else { return }
            addBackgroundQuad(c)
            flush()
            return
        }
        let canUseRenderPassClear = onSetClearColor != nil && appliedClearColor == c
        if !hasDrawnAnything && frameWillClear && clearColorApplied && canUseRenderPassClear {
            // Metal の loadAction = .clear がクリアを処理します。
            // 最初のフレームではこの最適化をスキップ: エンコーダーは
            // background() がクリアカラーを設定する前に作成されているため、
            // Metal のクリアは古いデフォルト（黒）を使用してしまいます。
            return
        }
        // 全画面クワッドを描画（既に何かが描画されているか、
        // loadAction = .load で明示的なクリアが必要な場合）。
        addBackgroundQuad(c)
        hasDrawnAnything = true
        flush()
    }

    /// キャンバス全体を覆う背景クワッドを積みます。
    ///
    /// 投影行列は「整数座標 = ピクセル中心」のハーフピクセル規約（``Canvas2D/init``）
    /// なので、`(0,0)-(width,height)` のクワッドはビューポート座標で `0.5 ..< w+0.5`
    /// しか覆わず、上端 1 行・左端 1 列のカバレッジが半分になる。MSAA 既定（4x）では
    /// これが「背景色 50% + クリアカラー 50%」として出力され、単一フレームの
    /// キャプチャ（`noLoop` / Probe snapshot / 1 フレーム目の `save()`）に常に残る（#373）。
    ///
    /// そのぶんだけ外へ広げてキャンバスの縁まで届かせる。はみ出した領域は
    /// ビューポート外なのでラスタライズ時に捨てられる。
    ///
    /// なお `rect(0, 0, width, height)` の縁が半分になるのは規約どおりの正しい挙動で、
    /// ここで補正するのは「キャンバス全体を塗る」という `background()` の意味論のみ。
    private func addBackgroundQuad(_ c: SIMD4<Float>) {
        let x0: Float = -0.5
        let y0: Float = -0.5
        let x1 = width - 0.5
        let y1 = height - 0.5
        addVertexRaw(x0, y0, c)
        addVertexRaw(x1, y0, c)
        addVertexRaw(x1, y1, c)
        addVertexRaw(x0, y0, c)
        addVertexRaw(x1, y1, c)
        addVertexRaw(x0, y1, c)
    }

    /// このフレームで指定された背景色が次回以降の render pass clear に反映されたことを記録します。
    func markPendingClearColorApplied() {
        guard let pendingClearColor else { return }
        appliedClearColor = pendingClearColor
        clearColorApplied = true
    }

    /// グレースケール値で背景を塗りつぶします。
    ///
    /// - Parameter gray: グレースケールの明度値。
    public func background(_ gray: Float) {
        background(colorModeConfig.toGray(gray))
    }

    /// カラーモード値を使用して背景を塗りつぶします。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。現在のカラーモードに従って解釈されます。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        background(colorModeConfig.toColor(v1, v2, v3, a))
    }
}
