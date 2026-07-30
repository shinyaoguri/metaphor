import Metal
import simd

extension Canvas3D {
    // MARK: - 変換スタック

    /// 変換、スタイル、マテリアルを含む全状態を保存します。
    public func pushState() {
        stateStack.append(StyleState3D(
            transform: currentTransform,
            fillColor: fillColor,
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            texture: currentTexture,
            colorModeConfig: colorModeConfig
        ))
    }

    /// 直前に保存した状態を復元します。
    public func popState() {
        guard let saved = stateStack.popLast() else { return }
        currentTransform = saved.transform
        fillColor = saved.fillColor
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        strokeColor = saved.strokeColor
        currentMaterial = saved.material
        currentCustomMaterial = saved.customMaterial
        currentTexture = saved.texture
        colorModeConfig = saved.colorModeConfig
    }

    /// 変換を除くスタイル状態（fill/stroke/material/texture/colorMode）のみを
    /// スタイル専用スタックに保存します。
    public func pushStyle() {
        styleOnlyStack.append(StyleState3D(
            transform: currentTransform,
            fillColor: fillColor,
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            texture: currentTexture,
            colorModeConfig: colorModeConfig
        ))
    }

    /// スタイル専用スタックからスタイル状態のみを復元します。変換は変更しません。
    public func popStyle() {
        guard let saved = styleOnlyStack.popLast() else { return }
        fillColor = saved.fillColor
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        strokeColor = saved.strokeColor
        currentMaterial = saved.material
        currentCustomMaterial = saved.customMaterial
        currentTexture = saved.texture
        colorModeConfig = saved.colorModeConfig
    }

    /// 現在の変換行列のみを保存します。
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// 直前に保存した変換行列のみを復元します。
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// 現在の変換に指定オフセットの平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: x軸方向の移動量。
    ///   - y: y軸方向の移動量。
    ///   - z: z軸方向の移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(translation: SIMD3(x, y, z))
    }

    /// 現在の変換をx軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateX(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationX: angle) }

    /// 現在の変換をy軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateY(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationY: angle) }

    /// 現在の変換をz軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateZ(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationZ: angle) }

    /// 各軸に沿った非均一スケールを現在の変換に適用します。
    ///
    /// - Parameters:
    ///   - x: x軸方向のスケール係数。
    ///   - y: y軸方向のスケール係数。
    ///   - z: z軸方向のスケール係数。
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(scale: SIMD3(x, y, z))
    }

    /// 全軸に均一スケールを現在の変換に適用します。
    ///
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) { currentTransform = currentTransform * float4x4(scale: s) }

    /// 現在の変換に指定した行列を乗算します。
    ///
    /// - Parameter matrix: 連結する 4x4 行列。
    public func applyMatrix(_ matrix: float4x4) {
        currentTransform = currentTransform * matrix
    }

    /// 現在の 3D 変換行列を単位行列にリセットします。
    public func resetMatrix() {
        currentTransform = .identity
    }

    /// モデル座標を現在のモデル変換・カメラ・投影でスクリーン座標へ変換します。
    ///
    /// - Parameters:
    ///   - x: モデル座標の x。
    ///   - y: モデル座標の y。
    ///   - z: モデル座標の z。
    /// - Returns: x/y はスクリーン座標（ピクセル単位）、z は NDC 深度（0...1）。
    ///   点がカメラ平面上（w = 0）の場合はゼロベクトル。
    public func screenPosition(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        // Swift 5.10 は行列×行列×ベクトルの連鎖式を型解決できないため分割する
        let modelViewProjection = computeViewProjection() * currentTransform
        let clip = modelViewProjection * SIMD4<Float>(x, y, z, 1)
        guard clip.w != 0 else { return .zero }
        let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
        // computeViewProjection は Y 反転（Processing の下向き規則）込みのため、
        // x/y とも (ndc + 1) / 2 でスクリーンへ写像する
        return SIMD3(
            (ndc.x + 1) / 2 * width,
            (ndc.y + 1) / 2 * height,
            ndc.z
        )
    }
}
