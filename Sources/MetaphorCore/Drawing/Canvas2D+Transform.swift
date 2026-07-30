import Metal
import simd

extension Canvas2D {
    // MARK: - 変換スタック

    /// 現在の変換とスタイル状態をスタックに保存します。
    ///
    /// ``pop()`` で保存した状態を復元します。Processing API と互換です。
    public func push() {
        stateStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// 直前に保存した変換とスタイル状態をスタックから復元します。
    ///
    /// ブレンドモードが変更された場合、現在のバッチをフラッシュします。Processing API と互換です。
    public func pop() {
        guard let saved = stateStack.popLast() else { return }
        // 保留中のジオメトリは現在のブレンドモードのパイプラインで描画する必要が
        // あるため、ブレンドモードを復元する「前」にフラッシュする
        // （flush は currentBlendMode のパイプラインを選択する）。
        if saved.blendMode != currentBlendMode {
            flush()
        }
        currentTransform = saved.transform
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
    }

    /// 変換を除くスタイル状態のみをスタイル専用スタックに保存します。
    public func pushStyle() {
        styleOnlyStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// スタイル専用スタックからスタイル状態のみを復元します。変換は変更しません。
    public func popStyle() {
        guard let saved = styleOnlyStack.popLast() else { return }
        // pop() と同様、ブレンドモード復元前に現在のモードでフラッシュする。
        if saved.blendMode != currentBlendMode {
            flush()
        }
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
    }

    /// 現在の変換行列のみをマトリクススタックに保存します。
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// マトリクススタックから変換行列のみを復元します。
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// 現在の変換に平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: ピクセル単位の水平方向移動量。
    ///   - y: ピクセル単位の垂直方向移動量。
    public func translate(_ x: Float, _ y: Float) {
        let t = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(x, y, 1)
        ))
        currentTransform = currentTransform * t
    }

    /// 現在の変換に回転を適用します。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotate(_ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        let r = float3x3(columns: (
            SIMD3<Float>(c, s, 0),
            SIMD3<Float>(-s, c, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * r
    }

    /// 現在の変換に非均一スケールを適用します。
    ///
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    public func scale(_ sx: Float, _ sy: Float) {
        let s = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * s
    }

    /// 現在の変換に均一スケールを適用します。
    ///
    /// - Parameter s: 両軸に適用するスケール係数。
    public func scale(_ s: Float) {
        scale(s, s)
    }

    /// 現在の 2D 変換に指定した行列を乗算します。
    ///
    /// - Parameter matrix: 連結する 3x3 行列。
    public func applyMatrix(_ matrix: float3x3) {
        currentTransform = currentTransform * matrix
    }

    /// 現在の 2D 変換に Processing 形式の 6 成分アフィン行列を乗算します。
    ///
    /// 成分は行優先で、変換は `x' = n00*x + n01*y + n02`、`y' = n10*x + n11*y + n12`。
    public func applyMatrix(
        _ n00: Float, _ n01: Float, _ n02: Float,
        _ n10: Float, _ n11: Float, _ n12: Float
    ) {
        applyMatrix(float3x3(columns: (
            SIMD3<Float>(n00, n10, 0),
            SIMD3<Float>(n01, n11, 0),
            SIMD3<Float>(n02, n12, 1)
        )))
    }

    /// 現在の 2D 変換行列を単位行列にリセットします。
    public func resetMatrix() {
        currentTransform = float3x3(1)
    }

    /// 現在の変換に x 軸方向のせん断（シアー）を適用します。
    ///
    /// `x' = x + tan(angle) * y`（Processing の `shearX()` と互換）。
    ///
    /// - Parameter angle: ラジアン単位のせん断角度。
    public func shearX(_ angle: Float) {
        let m = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(tan(angle), 1, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * m
    }

    /// 現在の変換に y 軸方向のせん断（シアー）を適用します。
    ///
    /// `y' = y + tan(angle) * x`（Processing の `shearY()` と互換）。
    ///
    /// - Parameter angle: ラジアン単位のせん断角度。
    public func shearY(_ angle: Float) {
        let m = float3x3(columns: (
            SIMD3<Float>(1, tan(angle), 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * m
    }

    /// モデル座標を現在の 2D 変換でスクリーン座標へ変換します。
    ///
    /// - Parameters:
    ///   - x: モデル座標の x。
    ///   - y: モデル座標の y。
    /// - Returns: スクリーン座標（ピクセル単位）。
    public func screenPosition(_ x: Float, _ y: Float) -> SIMD2<Float> {
        let p = currentTransform * SIMD3<Float>(x, y, 1)
        return SIMD2(p.x, p.y)
    }
}
