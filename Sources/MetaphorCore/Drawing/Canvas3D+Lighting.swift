import Metal
import simd

extension Canvas3D {
    // MARK: - ライティング

    /// 後方互換性のため、単一のディレクショナルライトでデフォルトライティングを有効にします。
    ///
    /// アンビエントは `colorMode` のレンジの 30%（既定レンジ 0〜255 なら
    /// `ambientLight(76.5)` 相当）に設定されます。
    public func lights() {
        flushInstanceBatch()  // 送信済みライトで確定してから差し替える
        lightArray.removeAll(keepingCapacity: true)
        applyDefaultAmbient()

        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        // ワールド +Y は画面下向きなので、上から差す光の向きは +Y。
        // 以前は y = -1 で、定義上「真下から」差していた（#774）。
        light.directionAndCutoff = SIMD4(-0.5, 1.0, -0.8, 0)
        light.colorAndIntensity = SIMD4(1, 1, 1, 0.7)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// シーンからすべてのライトを除去します。
    public func noLights() {
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        lightArray.removeAll(keepingCapacity: true)
    }

    /// 指定方向・色のディレクショナルライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト方向のx成分。
    ///   - y: ライト方向のy成分。
    ///   - z: ライト方向のz成分。
    ///   - color: ライトの色。
    ///   - intensity: ライトの強度倍率（既定 1.0）。色に乗算されます。
    ///     PBR（``pbr(_:)``）では直接光が `albedo / π` で減衰するため、
    ///     単灯で立体感を出すには 1.0 より大きい値（2〜4 程度）が要ります。
    public func directionalLight(
        _ x: Float, _ y: Float, _ z: Float, color: Color = .white, intensity: Float = 1.0
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        ensureAmbientIfFirstLight()
        // ローカル空間の方向をワールド空間に変換（w=0 で平行移動を除外）
        let td = currentTransform * SIMD4(x, y, z, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, 0)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, intensity)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// 指定位置にポイントライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置のx座標。
    ///   - y: ライト位置のy座標。
    ///   - z: ライト位置のz座標。
    ///   - color: ライトの色。
    ///   - falloff: 減衰フォールオフ係数。
    ///   - intensity: ライトの強度倍率（既定 1.0）。色に乗算されます。
    ///     PBR（``pbr(_:)``）では直接光が `albedo / π` で減衰するため、
    ///     単灯で立体感を出すには 1.0 より大きい値（2〜4 程度）が要ります。
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1,
        intensity: Float = 1.0
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        ensureAmbientIfFirstLight()
        // ローカル空間の位置をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 1)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, intensity)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, 0)
        lightArray.append(light)
    }

    /// 指定位置・方向にスポットライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置のx座標。
    ///   - y: ライト位置のy座標。
    ///   - z: ライト位置のz座標。
    ///   - dirX: スポットライト方向のx成分。
    ///   - dirY: スポットライト方向のy成分。
    ///   - dirZ: スポットライト方向のz成分。
    ///   - angle: 外側コーン角度（ラジアン）。
    ///   - falloff: 減衰フォールオフ係数。
    ///   - color: ライトの色。
    ///   - intensity: ライトの強度倍率（既定 1.0）。色に乗算されます。
    ///     PBR（``pbr(_:)``）では直接光が `albedo / π` で減衰するため、
    ///     単灯で立体感を出すには 1.0 より大きい値（2〜4 程度）が要ります。
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white,
        intensity: Float = 1.0
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        ensureAmbientIfFirstLight()
        let innerAngle = angle * 0.8
        // ローカル空間の位置と方向をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        let td = currentTransform * SIMD4(dirX, dirY, dirZ, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 2)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, cos(innerAngle))
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, intensity)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, cos(angle))
        lightArray.append(light)
    }

    /// 全チャンネル均一にアンビエントライトの強度を設定します。
    ///
    /// 値は `fill` と同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    /// 0〜1 のつもりの値（`ambientLight(0.35)` など）はほぼ真っ暗になります。
    /// `lights()` や最初のライト追加で入る既定アンビエントはレンジの 30%
    /// （`Canvas3D.defaultAmbientRatio`。既定レンジなら `ambientLight(76.5)`）です。
    ///
    /// - Parameter strength: R、G、B に適用されるアンビエントライト強度値
    ///   （`colorMode` のレンジ基準）。
    public func ambientLight(_ strength: Float) {
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        let c = colorModeConfig.toGray(strength)
        ambientColor = SIMD3(c.r, c.g, c.b)
        currentMaterial.ambientColor = SIMD4(c.r, c.g, c.b, 0)
        userSetAmbient = true
    }

    /// 個別の RGB 成分でアンビエントライトの色を設定します。
    ///
    /// 値は `fill` と同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        flushInstanceBatch()  // 送信済みシェイプを変更前のライトで確定
        let c = colorModeConfig.toColor(r, g, b, nil)
        ambientColor = SIMD3(c.r, c.g, c.b)
        currentMaterial.ambientColor = SIMD4(c.r, c.g, c.b, 0)
        userSetAmbient = true
    }
}
