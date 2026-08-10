import Metal
import simd

// 組み込みプリミティブと Mesh/DynamicMesh の描画入口、およびプリミティブメッシュの生成入口。
// メッシュキャッシュ（描画側の単位メッシュ・生成側の寸法込みメッシュ）もここが持つ。
extension Canvas3D {
    // MARK: - 3D プリミティブ

    /// 指定した寸法でボックスを描画します。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        // 単位メッシュをキャッシュし、寸法はモデル変換へ畳み込む。
        // 寸法入りキー（"box_w_h_d"）だと box(sin(t)*100) のような寸法アニメーションで
        // 毎フレーム新規メッシュ生成 + キャッシュ追い出しが起きる。法線は
        // normalMatrix（逆転置）で補正されるため非一様スケールでも正しい。
        guard let mesh = cachedMesh(key: "box_unit", create: {
            try Mesh.box(device: device, width: 1, height: 1, depth: 1)
        }) else { return }
        drawMeshScaled(mesh, scale: SIMD3(width, height, depth))
    }

    /// 同じ寸法の立方体を描画します。
    ///
    /// - Parameter size: 立方体の辺の長さ。
    public func box(_ size: Float) { box(size, size, size) }

    /// 指定した半径とテッセレーション詳細度で球を描画します。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: 経度方向のセグメント数（リングはここから導出されます）。
    public func sphere(_ radius: Float, detail: Int = 24) {
        let rings = max(detail / 2, 4)
        // 半径はモデル変換へ畳み込み、キーはテッセレーション詳細度のみにする
        let key = "sphere_unit_\(detail)_\(rings)"
        guard let mesh = cachedMesh(key: key, create: {
            try Mesh.sphere(device: device, radius: 1, segments: detail, rings: rings)
        }) else { return }
        drawMeshScaled(mesh, scale: SIMD3(repeating: radius))
    }

    /// 指定した寸法で平面を描画します。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    public func plane(_ width: Float, _ height: Float) {
        guard let mesh = cachedMesh(key: "plane_unit", create: {
            try Mesh.plane(device: device, width: 1, height: 1)
        }) else { return }
        drawMeshScaled(mesh, scale: SIMD3(width, height, 1))
    }

    /// 指定した半径、高さ、テッセレーション詳細度で円柱を描画します。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 放射方向のセグメント数。
    public func cylinder(radius: Float, height: Float, detail: Int = 24) {
        let key = "cylinder_unit_\(detail)"
        guard let mesh = cachedMesh(key: key, create: {
            try Mesh.cylinder(device: device, radius: 1, height: 1, segments: detail)
        }) else { return }
        drawMeshScaled(mesh, scale: SIMD3(radius, height, radius))
    }

    /// 指定した半径、高さ、テッセレーション詳細度で円錐を描画します。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 放射方向のセグメント数。
    public func cone(radius: Float, height: Float, detail: Int = 24) {
        let key = "cone_unit_\(detail)"
        guard let mesh = cachedMesh(key: key, create: {
            try Mesh.cone(device: device, radius: 1, height: 1, segments: detail)
        }) else { return }
        drawMeshScaled(mesh, scale: SIMD3(radius, height, radius))
    }

    /// 指定したリング半径とチューブ半径でトーラスを描画します。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブ中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: リング周囲の放射方向セグメント数。
    public func torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24) {
        let tubeDetail = max(detail / 2, 8)
        let key = "torus_\(ringRadius)_\(tubeRadius)_\(detail)_\(tubeDetail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.torus(device: device, ringRadius: ringRadius, tubeRadius: tubeRadius, segments: detail, tubeSegments: tubeDetail) }) else { return }
        drawMesh(mesh)
    }

    // MARK: - プリミティブメッシュの生成

    // 描画側（上の box/sphere/…）は単位メッシュ + スケールでキャッシュ churn を避けるが、
    // 「値としての Mesh」は変換を持てないので寸法込みで生成する。そのぶんキーも寸法込みで、
    // 描画側のキー（"box_unit" 等）とは "mesh_" prefix で分ける。
    //
    // 同じ引数の再呼び出しは同一インスタンスを返す（loadModel と同じ挙動）。毎フレーム
    // 寸法を変えて呼ぶとキャッシュが入れ替わり続けるため、生成は setup() が基本。

    /// 指定した寸法のボックスメッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createBoxMesh(_ width: Float, _ height: Float, _ depth: Float) -> Mesh? {
        cachedMesh(key: "mesh_box_\(width)_\(height)_\(depth)") {
            try Mesh.box(device: device, width: width, height: height, depth: depth)
        }
    }

    /// 同じ寸法の立方体メッシュを生成します（描画はしません）。
    ///
    /// - Parameter size: 立方体の辺の長さ。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createBoxMesh(_ size: Float) -> Mesh? { createBoxMesh(size, size, size) }

    /// 指定した半径とテッセレーション詳細度の球メッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: 経度方向のセグメント数（リングはここから導出されます）。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createSphereMesh(_ radius: Float, detail: Int = 24) -> Mesh? {
        let rings = max(detail / 2, 4)  // ``sphere(_:detail:)`` と同じ導出
        return cachedMesh(key: "mesh_sphere_\(radius)_\(detail)_\(rings)") {
            try Mesh.sphere(device: device, radius: radius, segments: detail, rings: rings)
        }
    }

    /// 指定した寸法の平面メッシュ（XY 平面・+Z 法線）を生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createPlaneMesh(_ width: Float, _ height: Float) -> Mesh? {
        cachedMesh(key: "mesh_plane_\(width)_\(height)") {
            try Mesh.plane(device: device, width: width, height: height)
        }
    }

    /// 指定した半径・高さ・テッセレーション詳細度の円柱メッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 放射方向のセグメント数。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createCylinderMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        cachedMesh(key: "mesh_cylinder_\(radius)_\(height)_\(detail)") {
            try Mesh.cylinder(device: device, radius: radius, height: height, segments: detail)
        }
    }

    /// 指定した半径・高さ・テッセレーション詳細度の円錐メッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 放射方向のセグメント数。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createConeMesh(radius: Float, height: Float, detail: Int = 24) -> Mesh? {
        cachedMesh(key: "mesh_cone_\(radius)_\(height)_\(detail)") {
            try Mesh.cone(device: device, radius: radius, height: height, segments: detail)
        }
    }

    /// 指定したリング半径とチューブ半径のトーラスメッシュを生成します（描画はしません）。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブ中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: リング周囲の放射方向セグメント数。
    /// - Returns: 生成されたメッシュ。失敗時は nil。
    public func createTorusMesh(ringRadius: Float, tubeRadius: Float, detail: Int = 24) -> Mesh? {
        let tubeDetail = max(detail / 2, 8)  // ``torus(ringRadius:tubeRadius:detail:)`` と同じ導出
        return cachedMesh(key: "mesh_torus_\(ringRadius)_\(tubeRadius)_\(detail)_\(tubeDetail)") {
            try Mesh.torus(
                device: device, ringRadius: ringRadius, tubeRadius: tubeRadius,
                segments: detail, tubeSegments: tubeDetail
            )
        }
    }

    /// キャッシュ済みメッシュを検索または生成します。失敗時はエラーをログ出力します。
    private func cachedMesh(key: String, create: () throws -> Mesh) -> Mesh? {
        if var cached = meshCache[key] {
            cached.lastUsedFrame = meshCacheFrameCounter
            meshCache[key] = cached
            return cached.mesh
        }
        do {
            let mesh = try create()
            meshCache[key] = CachedMesh(mesh: mesh, lastUsedFrame: meshCacheFrameCounter)
            if meshCache.count > Self.maxMeshCacheSize {
                evictStaleMeshes()
            }
            return mesh
        } catch {
            print("[metaphor] Failed to create mesh '\(key)': \(error)")
            return nil
        }
    }

    /// メッシュキャッシュの最も古い半分を削除します。
    private func evictStaleMeshes() {
        let sorted = meshCache.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        let removeCount = meshCache.count - Self.maxMeshCacheSize / 2
        for (key, _) in sorted.prefix(removeCount) {
            meshCache.removeValue(forKey: key)
        }
    }

    /// スケールをモデル変換へ一時的に畳み込んでメッシュを描画します。
    ///
    /// 単位メッシュ + スケールでプリミティブの寸法アニメーションによる
    /// メッシュキャッシュ churn を防ぐ。スケール成分 0 は normalMatrix
    /// （逆転置）が特異になるため微小値へ退避する。
    private func drawMeshScaled(_ mesh: Mesh, scale: SIMD3<Float>) {
        func safe(_ v: Float) -> Float { v == 0 ? 1e-6 : v }
        let saved = currentTransform
        currentTransform = currentTransform * float4x4(
            scale: SIMD3(safe(scale.x), safe(scale.y), safe(scale.z))
        )
        drawMesh(mesh)
        currentTransform = saved
    }

    /// ビルド済みメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するメッシュ。
    public func mesh(_ mesh: Mesh) { drawMesh(mesh) }

    /// 同一メッシュを複数のトランスフォームで一括描画します（明示インスタンシング）。
    ///
    /// - Parameters:
    ///   - mesh: 描画するメッシュ。
    ///   - transforms: インスタンスごとのローカル変換。現在の変換行列に右から掛かります。
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4]) {
        drawMeshInstanced(mesh, transforms: transforms, colors: nil)
    }

    /// 同一メッシュを、インスタンスごとの fill 色つきで一括描画します。
    ///
    /// - Parameters:
    ///   - mesh: 描画するメッシュ。
    ///   - transforms: インスタンスごとのローカル変換。現在の変換行列に右から掛かります。
    ///   - colors: インスタンスごとの fill 色。不足分は現在の fill 色、余りは無視されます。
    public func drawInstanced(_ mesh: Mesh, transforms: [float4x4], colors: [Color]) {
        drawMeshInstanced(mesh, transforms: transforms, colors: colors.map(\.simd))
    }

    /// 実行時の頂点変更に対応するダイナミックメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するダイナミックメッシュ。
    public func dynamicMesh(_ mesh: DynamicMesh) {
        guard hasFill || hasStroke else { return }

        // 記録経路（影オン / METAPHOR_COMMAND_RECORD）: 現在の内容を不変の
        // Mesh として複製し、drawMesh の記録経路（DrawCall3D）に載せる。従来は
        // encoder 必須の即時経路しかなく、記録フレームでは本体が消失していた（#152）
        if shouldRecordMainPass && !isReplaying {
            if let snapshot = mesh.makeSnapshotMesh() {
                drawMesh(snapshot)
            }
            return
        }

        mesh.ensureBuffers()
        guard let encoder = encoder,
              let vb = mesh.vertexBuffer else { return }

        // DynamicMesh はインスタンシング対象外
        flushInstanceBatch()

        // UV を宣言したメッシュに texture() が設定されているときだけテクスチャ経路へ入る
        // （UV 未宣言のメッシュを全頂点 uv=(0,0) でサンプルしないため・#435）
        let uvBuffer = mesh.uvVertexBuffer
        let isTextured = currentTexture != nil && uvBuffer != nil

        encoder.setRenderPipelineState(isTextured ? texturedPipelineState : pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setVertexBuffer(isTextured ? uvBuffer : vb, offset: 0, index: 0)

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

            if isTextured, let tex = currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }
        }

        if hasStroke {
            encoder.setTriangleFillMode(.lines)

            // stroke は頂点カラーを無視して stroke 色だけで描く（#429 / #436）。
            // wirePipelineState は positionNormalColor なので、fill でテクスチャ経路
            // （positionNormalUV）に入っていた場合も UV なしの頂点列へ貼り直す
            encoder.setRenderPipelineState(wirePipelineState)
            encoder.setVertexBuffer(vb, offset: 0, index: 0)

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

            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            Canvas3D.beginStrokeDepthBias(on: encoder)
            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }
            Canvas3D.endStrokeDepthBias(on: encoder)

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - メッシュキャッシュ


    /// メッシュキャッシュをクリアし、キャッシュ済みの GPU メッシュバッファをすべて解放します。
    public func clearMeshCache() {
        meshCache.removeAll()
    }
}
