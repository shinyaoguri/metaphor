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
        backgroundCalledThisFrame = true
        pendingClearColor = c
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        // シャドウ同一フレーム化の遅延モードでは、メインパスの loadAction = .clear が
        // クリアを担う（endFrame の setShouldClear が同フレームで反映される）。
        // ここでクワッドを描くと前景キューに乗って 3D を覆うため、描かずに戻る（#70）。
        if isDeferring { return }
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
        addVertexRaw(0, 0, c)
        addVertexRaw(width, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, height, c)
        hasDrawnAnything = true
        flush()
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
