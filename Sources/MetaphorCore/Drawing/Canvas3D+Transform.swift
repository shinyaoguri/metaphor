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

    /// モデル座標を現在のモデル変換だけで写した**ワールド座標**を返します。
    ///
    /// `translate` / `rotateX/Y/Z` / `scale` / ``applyMatrix(_:)`` を積んだ状態でローカル
    /// 座標を渡すと、その点がワールド空間のどこに来るかが返ります（Processing の
    /// `modelX()` / `modelY()` / `modelZ()` 相当）。``screenPosition(_:_:_:)`` と違って
    /// カメラも投影も通さないため、``camera(eye:center:up:)`` や
    /// ``perspective(fov:near:far:)`` を変えても戻り値は変わりません。
    ///
    /// - Note: Processing の実装は `cameraInv * modelview * point`
    ///   （`modelview = camera * currentMatrix`）で、カメラが打ち消し合って実質
    ///   `currentMatrix * point` になります。metaphor はカメラを `currentTransform` と
    ///   分けて持つため、打ち消しの往復なしに現在の変換行列だけを掛けます。
    ///
    /// - Parameters:
    ///   - x: モデル座標の x。
    ///   - y: モデル座標の y。
    ///   - z: モデル座標の z。
    /// - Returns: ワールド座標。
    public func modelPosition(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        let world = currentTransform * SIMD4<Float>(x, y, z, 1)
        let xyz = SIMD3<Float>(world.x, world.y, world.z)
        // Processing と同じ扱い: w が 0 なら除算せずそのまま返す。translate / rotate /
        // scale だけなら w は常に 1 で、0 になり得るのは applyMatrix(_:) に射影成分を
        // 含む行列を渡した場合だけ。
        guard world.w != 0 else { return xyz }
        return xyz / world.w
    }

    /// モデル座標を現在のモデル変換・カメラ・投影でスクリーン座標へ変換します。
    ///
    /// - Important: **カメラ背後の点では反転した値が返ります。**透視投影では
    ///   カメラ平面より後ろの点がクリップ空間で `w < 0` になり、遠近除算で x/y が
    ///   原点対称に反転し z も 0...1 を外れます。戻り値だけでは前方の点と区別できないため、
    ///   ラベル配置やカリングに使う前に ``isInFront(_:_:_:)`` で弾いてください。
    /// - Note: z が 0...1 に収まるのは点が視錐台の内側にあるときだけです。
    ///   カメラとニア平面のあいだ（`w > 0` だが視錐台の外）では反転しませんが値が発散します。
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
        // computeViewProjection は Y 反転（Processing の下向き規則）込みのため、NDC 空間では
        // 画面上側が +Y になる。ピクセル座標は上側が y=0 なので、x とは逆に
        // (1 - ndc.y) / 2 で写像し、2D の screenY(_:_:) と同じ座標系（左上原点・下方向が +Y）にする。
        return SIMD3(
            (ndc.x + 1) / 2 * width,
            (1 - ndc.y) / 2 * height,
            ndc.z
        )
    }

    /// モデル座標の点がカメラ平面より前にある（= ``screenPosition(_:_:_:)`` の
    /// 戻り値が反転していない）かを返します。
    ///
    /// 透視投影ではカメラ背後の点がクリップ空間で `w < 0` になり、遠近除算で
    /// スクリーン座標が原点対称に反転します。この判定を挟むと、背後の物にラベルが
    /// 付いたり視界外の点を「画面内」と誤判定したりするのを防げます。
    ///
    /// ```swift
    /// if isInFront(px, py, pz) {
    ///     text("label", screenX(px, py, pz), screenY(px, py, pz))
    /// }
    /// ```
    ///
    /// - Note: true は「反転していない」ことだけを保証し、「画面内にある」ことも
    ///   「深度が 0...1 に収まる」ことも保証しません。視錐台の内外は
    ///   ``screenPosition(_:_:_:)`` の x/y と z を見て別途判定してください。
    /// - Note: 正射影（``ortho(left:right:bottom:top:near:far:)``）には遠近除算が
    ///   無く反転そのものが起きないため、常に true を返します。既定の `ortho()` は
    ///   ニアを負に取ってカメラ背後まで写すので、ここで背後を弾くと見えている
    ///   ものまで落ちてしまいます。
    ///
    /// - Parameters:
    ///   - x: モデル座標の x。
    ///   - y: モデル座標の y。
    ///   - z: モデル座標の z。
    /// - Returns: カメラ平面より前なら true。背後、またはカメラ平面上（w = 0、
    ///   ``screenPosition(_:_:_:)`` がゼロベクトルを返す位置）なら false。
    public func isInFront(_ x: Float, _ y: Float, _ z: Float) -> Bool {
        // Swift 5.10 は行列×行列×ベクトルの連鎖式を型解決できないため分割する
        let modelViewProjection = computeViewProjection() * currentTransform
        let clip = modelViewProjection * SIMD4<Float>(x, y, z, 1)
        return clip.w > 0
    }
}
