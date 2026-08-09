import Metal
import simd

extension Canvas3D {
    // MARK: - 内部描画

    // インスタンシングパスまたはイミディエイトフォールバックを通してメッシュ描画をルーティング
    func drawMesh(_ mesh: Mesh) {
        guard hasFill || hasStroke else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        // 記録経路（影オン、またはコマンド記録 opt-in）では、ライブ描画で「記録のみ」を行い、
        // メインパスへの実エンコードは再生（replayRecordedRange）まで遅延する。影オンでは
        // 同一フレームのシャドウ（影N）をサンプルでき動く影の遅延が解消（#70）、コマンド記録では
        // 2D と呼び出し順でインターリーブできる（#71）。即時経路と replay 中は即時エンコード。
        if shouldRecordMainPass && !isReplaying {
            // 2D の保留バッチを先に確定し、その seq を「この 3D 記録より前」に固定する（宿題①）。
            flushPending2D?()
            recordedDrawCalls.append(DrawCall3D(
                mesh: mesh,
                transform: currentTransform,
                fillColor: fillColor,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                texture: currentTexture,
                isTextured: isTextured,
                hasFill: hasFill,
                hasStroke: hasStroke,
                strokeColor: strokeColor,
                seq: seqProvider?() ?? 0,
                stateSnapshot: snapshotForRecording()
            ))
            return
        }

        // メインパスへの実エンコード（影オフのライブ描画、または影オンの replay）。
        guard encoder != nil else { return }

        // カスタム頂点シェーダーはインスタンシング不可; イミディエイトパスにフォールバック
        if let customMat = currentCustomMaterial, customMat.vertexFunction != nil {
            flushInstanceBatch()
            drawMeshImmediate(mesh)
            return
        }

        // バッチキーを生成
        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let key = BatchKey3D(
            meshID: ObjectIdentifier(mesh),
            isTextured: isTextured,
            textureID: currentTexture.map { ObjectIdentifier($0 as AnyObject) },
            material: currentMaterial,
            customMaterialID: currentCustomMaterial.map { ObjectIdentifier($0) },
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor
        )

        // インスタンスバッチへの蓄積を試みる
        if !instanceBatcher.tryAddInstance(
            key: key,
            mesh: mesh,
            texture: currentTexture,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor,
            transform: currentTransform,
            normalMatrix: normalMatrix,
            color: fillColor
        ) {
            // キー不一致またはバッファ満杯; 現在のバッチをフラッシュしてリトライ
            flushInstanceBatch()
            if !instanceBatcher.tryAddInstance(
                key: key,
                mesh: mesh,
                texture: currentTexture,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                hasFill: hasFill,
                hasStroke: hasStroke,
                strokeColor: strokeColor,
                transform: currentTransform,
                normalMatrix: normalMatrix,
                color: fillColor
            ) {
                // リトライも失敗; 非インスタンスド描画にフォールバック
                drawMeshImmediate(mesh)
            }
        }
    }

    // MARK: - インスタンスバッチフラッシュ

    /// 蓄積されたインスタンスを単一のインスタンス描画コールとしてフラッシュします。
    func flushInstanceBatch() {
        guard let encoder = encoder,
              instanceBatcher.instanceCount > 0,
              let mesh = instanceBatcher.currentMesh else { return }

        let isTextured = instanceBatcher.currentBatchKey?.isTextured ?? false
        let batchHasFill = instanceBatcher.currentHasFill
        let batchHasStroke = instanceBatcher.currentHasStroke

        // パイプラインを選択
        if let customMat = instanceBatcher.currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? instancedTexturedPipelineState : instancedPipelineState)
        }

        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        // 頂点バッファ
        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // インスタンスバッファを buffer(6) に設定
        encoder.setVertexBuffer(instanceBatcher.currentBuffer, offset: instanceBatcher.currentBufferOffset, index: 6)

        // --- 塗りつぶしパス ---
        if batchHasFill {
            var sceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )
            encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            // ライト
            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            // マテリアル
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // カスタムマテリアルパラメータ
            if let customMat = instanceBatcher.currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            // シャドウ
            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(dummyShadowTexture, index: 1)
            }

            // テクスチャ
            if isTextured, let tex = instanceBatcher.currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            // インスタンス描画
            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                let vc = isTextured ? mesh.uvVertexCount : mesh.vertexCount
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: vc,
                    instanceCount: instanceBatcher.instanceCount
                )
            }
        }

        // --- ワイヤーフレーム（ストローク）パス ---
        if batchHasStroke {
            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(instancedWirePipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)

            // ワイヤーフレームはライティングなし（lightCount=0）。ストローク色は
            // 全インスタンスで統一（BatchKey が同一 strokeColor を要求する）なので、
            // インスタンスバッファを書き換えず buffer(4) で 1 色だけ渡す。
            // インスタンス色（= fill 色）を流用していたときは stroke 色が反映されず、
            // 頂点カラーとの乗算で線が消えることもあった（#429）
            var wireColor = instanceBatcher.currentStrokeColor
            encoder.setVertexBytes(&wireColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)

            var wireSceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )
            encoder.setVertexBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // ワイヤーフレームではシャドウ無効
            var shadowOff = ShadowFragmentUniforms(lightSpaceMatrix: .identity, shadowBias: 0, shadowEnabled: 0)
            encoder.setFragmentBytes(&shadowOff, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
            encoder.setFragmentTexture(dummyShadowTexture, index: 1)

            Canvas3D.beginStrokeDepthBias(on: encoder)
            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount,
                    instanceCount: instanceBatcher.instanceCount
                )
            }
            Canvas3D.endStrokeDepthBias(on: encoder)

            encoder.setTriangleFillMode(.fill)
        }

        instanceBatcher.reset()
    }

    // MARK: - イミディエイト描画（フォールバック、非インスタンス）

    // インスタンシングなしでメッシュを描画（カスタム頂点シェーダー用フォールバック）
    private func drawMeshImmediate(_ mesh: Mesh) {
        guard let encoder = encoder else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        if let customMat = currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured, customVertexFunction: customMat.vertexFunction) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? texturedPipelineState : pipelineState)
        }
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // --- 塗りつぶしパス ---
        if hasFill {
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let customMat = currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(dummyShadowTexture, index: 1)
            }

            if isTextured, let tex = currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: isTextured ? mesh.uvVertexCount : mesh.vertexCount
                )
            }
        }

        // --- ワイヤーフレーム（ストローク）パス ---
        if hasStroke {
            encoder.setTriangleFillMode(.lines)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            // 頂点カラーを無視して stroke 色だけで描く（#429）
            encoder.setRenderPipelineState(wirePipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            Canvas3D.beginStrokeDepthBias(on: encoder)
            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: mesh.vertexCount
                )
            }
            Canvas3D.endStrokeDepthBias(on: encoder)

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - カスタムパイプライン

    /// カスタムパイプラインキャッシュをクリアします。通常、シェーダーホットリロード後に呼び出します。
    public func clearCustomPipelineCache() {
        customPipelineCache.removeAll()
    }

    // キャッシュ済みカスタムシェーダーパイプラインを取得または生成
    private func getCustomPipeline(fragmentFunction: MTLFunction, isTextured: Bool, customVertexFunction: MTLFunction? = nil) -> MTLRenderPipelineState? {
        let vtxName = customVertexFunction?.name ?? "default"
        let cacheKey = "\(fragmentFunction.name)_\(vtxName)_\(isTextured)_\(sampleCount)"
        if var cached = customPipelineCache[cacheKey] {
            cached.lastUsedFrame = meshCacheFrameCounter
            customPipelineCache[cacheKey] = cached
            return cached.pipeline
        }

        let vertexFn: MTLFunction?
        let layout: VertexLayout

        if let customVtx = customVertexFunction {
            vertexFn = customVtx
            layout = isTextured ? .positionNormalUV : .positionNormalColor
        } else if isTextured {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
                from: ShaderLibrary.BuiltinKey.canvas3DTextured
            )
            layout = .positionNormalUV
        } else {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DVertex,
                from: ShaderLibrary.BuiltinKey.canvas3D
            )
            layout = .positionNormalColor
        }

        guard let pipeline = try? PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFunction)
            .vertexLayout(layout)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()
        else {
            return nil
        }

        customPipelineCache[cacheKey] = CachedPipeline(pipeline: pipeline, lastUsedFrame: meshCacheFrameCounter)
        if customPipelineCache.count > 32 {
            let sorted = customPipelineCache.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
            let removeCount = customPipelineCache.count - 16
            for (key, _) in sorted.prefix(removeCount) {
                customPipelineCache.removeValue(forKey: key)
            }
        }
        return pipeline
    }
}
