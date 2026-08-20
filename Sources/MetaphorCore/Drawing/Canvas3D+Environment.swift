import Metal
import simd

// 環境（IBL / skybox）。Epic #293 の G3b（Issue #710）。
extension Canvas3D {

    // MARK: - 公開 API

    /// 環境（IBL と skybox）を設定します。
    ///
    /// - Parameters:
    ///   - preset: 環境プリセット。
    ///   - intensity: 環境の強度（既定 1.0）。0 以下で無効。
    ///   - background: `true` なら背景として skybox も描く。
    public func environment(
        _ preset: EnvironmentPreset,
        intensity: Float = 1.0,
        background: Bool = true
    ) {
        // 設定前に送信済みのシェイプを、変更前の環境で確定させる
        flushInstanceBatch()

        do {
            environment = try IBLEnvironment.shared(
                preset: preset, device: device, shaderLibrary: shaderLibrary)
        } catch {
            metaphorWarning("environment(): 環境の生成に失敗したため IBL は無効のままです (\(error))")
            environment = nil
            return
        }

        environmentIntensity = max(intensity, 0)
        environmentShowsBackground = background
        toneMapParams.z = environmentIntensity
        currentMaterial.toneMapParams = toneMapParams

        // IBL を入れると輝度は容易に 1.0 を超えるので、トーンマップ未指定なら
        // ACES filmic へ自動昇格させる（明示指定は尊重する）
        if !userSetToneMapping && toneMapParams.x == Float(ToneMapMode.none.rawValue) {
            toneMapParams.x = Float(ToneMapMode.acesFilmic.rawValue)
            currentMaterial.toneMapParams = toneMapParams
        }

        // 既定アンビエントは IBL の拡散項と二重計上になるので落とす。
        // `ambientLight()` を明示していれば、そちらを優先して残す。
        if !userSetAmbient {
            applyDefaultAmbient()
        }
    }

    /// 環境を無効化します。IBL と skybox の両方が消え、既定のアンビエントに戻ります。
    public func noEnvironment() {
        flushInstanceBatch()

        environment = nil
        environmentIntensity = 0
        toneMapParams.z = 0
        currentMaterial.toneMapParams = toneMapParams

        if !userSetAmbient {
            applyDefaultAmbient()
        }
    }

    // MARK: - リソースのバインド

    /// 3D フラグメントシェーダーが要求する環境キューブ（`texture(2)` = イラディアンス /
    /// `texture(3)` = プリフィルタ済み鏡面）をバインドします。
    ///
    /// シェーダー引数は非オプショナルなので、環境が無効でもダミーをバインドする
    /// （``Canvas3D/bindShadowResources(on:enabled:)`` と同じ理由）。強度は
    /// `Material3D.toneMapParams.z` で運ばれ、0 のとき IBL の寄与は 0 になる。
    func bindEnvironmentResources(on encoder: MTLRenderCommandEncoder, enabled: Bool = true) {
        if enabled, let environment = environment {
            encoder.setFragmentTexture(environment.irradianceTexture, index: 2)
            encoder.setFragmentTexture(environment.prefilteredTexture, index: 3)
        } else {
            encoder.setFragmentTexture(dummyEnvironmentCube, index: 2)
            encoder.setFragmentTexture(dummyEnvironmentCube, index: 3)
        }
    }

    // MARK: - skybox

    /// このフレームでまだ skybox を描いていなければ描きます。
    ///
    /// **最初の 3D 描画の直前**に 1 回だけ呼ばれる（各エンコード経路の入口から）。
    /// カメラが確定していて、かつ 3D ジオメトリより前に出せる唯一の位置。
    /// 深度を書かずに最奥（1.0）を `lessEqual` で通すので、この時点でまだ何も
    /// 深度を書いていない画面は全面が塗られる。したがって skybox より前に描いた
    /// 2D は覆われ、後に描いた 2D（HUD などの前景）はそのまま上に残る。
    func ensureSkyboxDrawn() {
        guard !skyboxDrawnThisFrame else { return }
        guard let environment = environment,
              environmentShowsBackground,
              environmentIntensity > 0,
              let encoder = encoder else { return }

        skyboxDrawnThisFrame = true

        guard let pipeline = ensureSkyboxPipeline() else { return }

        var uniforms = SkyboxUniforms(
            inverseViewProjection: computeViewProjection().inverse,
            cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
            params: SIMD4(environmentIntensity, toneMapParams.x, toneMapParams.y, 0)
        )

        encoder.setRenderPipelineState(pipeline)
        if let skyboxDepthState = skyboxDepthState {
            encoder.setDepthStencilState(skyboxDepthState)
        }
        encoder.setCullMode(.none)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SkyboxUniforms>.stride, index: 0)
        encoder.setFragmentTexture(environment.environmentTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // 呼び出し元は直後に自分のパイプラインを張り直すが、デプスステートは
        // 経路によっては張り直さないので、ここで通常の 3D 用へ戻しておく
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
    }

    /// skybox パイプラインとデプスステートを遅延生成します。
    ///
    /// シェーダーは常駐コンパイルせず、環境が実際に使われたときだけ登録する
    /// （``ShadowMap`` の `metaphor.shadowDepth` と同じ扱い）。
    private func ensureSkyboxPipeline() -> MTLRenderPipelineState? {
        if let skyboxPipelineState = skyboxPipelineState { return skyboxPipelineState }

        let key = "metaphor.skybox"
        do {
            if !shaderLibrary.hasLibrary(for: key) {
                guard let source = ShaderLibrary.loadShaderSource("skybox") else {
                    throw MetaphorError.shaderNotFound("skybox")
                }
                try shaderLibrary.register(source: source, as: key)
            }
            guard let vertexFn = shaderLibrary.function(named: "metaphor_skyboxVertex", from: key),
                  let fragmentFn = shaderLibrary.function(named: "metaphor_skyboxFragment", from: key) else {
                throw MetaphorError.shaderNotFound("metaphor_skyboxVertex/Fragment")
            }

            // 深度は書かず `lessEqual` で比較する。skybox は NDC の最奥（深度 1.0）に
            // 置くので、3D ジオメトリが後から書いた場所では自然に負ける。
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .lessEqual
            depthDescriptor.isDepthWriteEnabled = false
            skyboxDepthState = device.makeDepthStencilState(descriptor: depthDescriptor)

            let pipeline = try PipelineFactory(device: device)
                .vertex(vertexFn)
                .fragment(fragmentFn)
                .sampleCount(sampleCount)
                .build()
            skyboxPipelineState = pipeline
            return pipeline
        } catch {
            metaphorWarning("environment(): skybox パイプラインを作成できませんでした (\(error))")
            return nil
        }
    }
}
