import Metal
import simd

extension Canvas3D {
    // MARK: - フレームライフサイクル

    /// フレームごとの状態をリセットし、レンダーエンコーダーを設定して新しいフレームを開始します。
    func begin(encoder: MTLRenderCommandEncoder?, time: Float, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentTime = time
        // フレームごとの状態をリセット（変換、カメラ、ライト、ドローコール）
        self.currentTransform = .identity
        self.stateStack.removeAll(keepingCapacity: true)
        self.styleOnlyStack.removeAll(keepingCapacity: true)
        // 不均衡な pushMatrix() が draw() 内に残っていても、フレームを
        // またいでスタックが無限成長したり変換がリークしたりしないよう、
        // stateStack と同様に毎フレーム破棄する。
        self.matrixStack.removeAll(keepingCapacity: true)
        self.lightArray.removeAll(keepingCapacity: true)
        self.ambientColor = SIMD3(0.2, 0.2, 0.2)
        self.userSetAmbient = false
        self.currentMaterial = .default
        // `Material3D.default` のアンビエントはフレームごとに戻るので、環境が
        // 有効な間は毎フレーム 0 へ焼き直す（IBL との二重計上を避ける・#710）
        if environment != nil {
            applyDefaultAmbient()
        }
        self.currentTexture = nil
        self.currentCustomMaterial = nil
        self.recordedDrawCalls.removeAll(keepingCapacity: true)
        self.skyboxDrawnThisFrame = false
        self.meshCacheFrameCounter += 1

        // 各フレームで Processing 風のデフォルトに投影をリセット。
        // カスタム投影には毎フレーム perspective()/ortho() を呼ぶ必要があります。
        let defaultZ = defaultCameraZ
        self.fov = Canvas3D.defaultFov
        self.nearPlane = defaultZ / 10
        self.farPlane = defaultZ * 10
        self.cameraEye = SIMD3(width / 2, height / 2, defaultZ)
        self.cameraCenter = SIMD3(width / 2, height / 2, 0)
        self.cameraUp = SIMD3(0, 1, 0)
        self.viewProjectionDirty = true
        self.useOrthographic = false

        // シェイプ頂点リングを回転（in-flight フレームと書き込み先を分離）し、
        // バンプカーソルをリセット
        self.shapeVertexBufferIndex = bufferIndex
        self.shapeVertexBufferUsed = 0

        // スタイル状態（fill、stroke）はフレーム間で保持される。
        // Processing の動作に合わせます。
        instanceBatcher.beginFrame(bufferIndex: bufferIndex)
    }

    /// 保留中のインスタンスバッチをフラッシュして現在のフレームを終了します。
    func end() {
        flushInstanceBatch()
        self.encoder = nil
    }

    /// メインパス分割後（`loadPixels()` の同一フレーム読み戻し、#326）に、
    /// 描画先を新しいレンダーコマンドエンコーダへ差し替えます。
    ///
    /// 呼び出し側は分割前に ``flushInstanceBatch()`` 済みであること。カメラ・ライト・
    /// 変換などフレーム状態は維持する（`draw()` の途中のため）。
    ///
    /// - Note: 継続パスはデプスがクリアされる。分割をまたいだ 3D 同士は深度比較されない。
    /// - Parameter newEncoder: 継続パスのレンダーコマンドエンコーダー。
    func rebindEncoder(_ newEncoder: MTLRenderCommandEncoder) {
        self.encoder = newEncoder
    }

    /// メインレンダリングパス完了後にシャドウ深度パスを実行します。
    func performShadowPass(commandBuffer: MTLCommandBuffer) {
        guard let shadow = shadowMap, !recordedDrawCalls.isEmpty else { return }

        // 最初のディレクショナルライトからライト空間行列を計算
        if let dirLight = lightArray.first(where: { UInt32($0.positionAndType.w) == 0 }) {
            let lightDir = SIMD3(dirLight.directionAndCutoff.x, dirLight.directionAndCutoff.y, dirLight.directionAndCutoff.z)
            shadow.updateLightSpaceMatrix(lightDirection: lightDir, sceneCenter: cameraCenter)
        }

        shadow.render(drawCalls: recordedDrawCalls, commandBuffer: commandBuffer)
    }

    // MARK: - シャドウリソースのバインド

    /// 3D フラグメントシェーダーが要求するシャドウリソース（`buffer(5)` のユニフォームと
    /// `texture(1)` のシャドウマップ）をバインドします。
    ///
    /// 組み込み 3D フラグメントシェーダーは**すべて**シャドウと環境を引数に取るため、
    /// `pipelineState` / `texturedPipelineState` / `wirePipelineState` /
    /// インスタンス系パイプラインのどれで描く場合も、描画前に必ず呼ぶこと
    /// （バインド漏れは Metal のバリデーションで落ちる）。
    ///
    /// 環境（IBL）のキューブマップも同時にバインドする。呼び出し側を 1 か所に
    /// 保つため、シャドウと環境をこの 1 本にまとめている（#710）。
    ///
    /// - Parameters:
    ///   - encoder: バインド先のレンダーコマンドエンコーダー。
    ///   - enabled: `false` ならシャドウ・環境ともに無効のユニフォームとダミー
    ///     テクスチャをバインドする。ライティングを行わないワイヤーフレーム
    ///     （stroke）パス用。
    func bindShadowResources(on encoder: MTLRenderCommandEncoder, enabled: Bool = true) {
        bindEnvironmentResources(on: encoder, enabled: enabled)

        if enabled, let shadow = shadowMap {
            var uniforms = ShadowFragmentUniforms(
                lightSpaceMatrix: shadow.lightSpaceMatrix,
                shadowBias: shadow.shadowBias,
                shadowEnabled: 1.0
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
            encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
        } else {
            var uniforms = ShadowFragmentUniforms(
                lightSpaceMatrix: .identity,
                shadowBias: 0,
                shadowEnabled: 0
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
            encoder.setFragmentTexture(dummyShadowTexture, index: 1)
        }
    }
}
