import Metal
import simd

// テッセレーション済みシェイプ頂点の GPU エンコード（Canvas3D+Shapes.swift から呼ばれる）。
extension Canvas3D {
    // MARK: - fill の適用回数（#825）

    // beginShape/endShape の頂点カラーには、記録の時点で「fill 色」または
    // 「vertex(…color:) で与えた色」が焼き込まれている（Canvas3D+Shapes.swift）。
    // 頂点シェーダーは `in.color * uniforms.color` を掛けるので、uniforms 側にも
    // fill を送ると fill が 2 回掛かる（#825）。頂点カラーが白の組み込みメッシュ
    // （Mesh.swift）と違い、シェイプ側は uniforms を白にして 1 回に揃える。
    //
    // 焼き込みをやめて uniforms 一本にしないのは、beginShape の途中で fill() を
    // 変える書き方（Processing 由来の頂点ごとの色づけ）を保つため。
    static let bakedShapeTint = SIMD4<Float>(1, 1, 1, 1)

    // 記録経路（影オン / METAPHOR_COMMAND_RECORD）は drawMesh 経由になり、
    // drawMesh は現在の fillColor を DrawCall3D へ載せる。焼き込み済みの頂点を
    // 渡すあいだだけ fill を白へ退避して、即時経路と同じ結果にする（#825）。
    func drawBakedShapeMesh(_ mesh: Mesh) {
        let savedFill = fillColor
        fillColor = Canvas3D.bakedShapeTint
        defer { fillColor = savedFill }
        drawMesh(mesh)
    }

    // MARK: - Mesh 経由へ落とす条件

    // テッセレーション済み頂点を一時 Mesh 化して drawMesh へ渡すべきか。
    // この下の即時エンコードは組み込みパイプラインを直に張る簡略版なので、
    // 次の 2 つは drawMesh 側の道具立てが要る:
    //
    // - 記録経路（影オン / METAPHOR_COMMAND_RECORD）: DrawCall3D として記録し、
    //   同一フレームのシャドウへ落とす（#152）
    // - カスタムマテリアル: パイプライン選択（`getCustomPipeline`）と buffer(4) の
    //   パラメータ束縛は drawMeshImmediate にしかなく、即時エンコードは
    //   `currentCustomMaterial` を一切見ていなかった。そのため `material(_:)` が
    //   メッシュ／プリミティブにだけ効き、`beginShape3D` のシェイプには効かない
    //   （かつ影オンでは効く）という食い違いになっていた（#826）
    var shouldRouteShapeThroughMesh: Bool {
        (shouldRecordMainPass && !isReplaying) || currentCustomMaterial != nil
    }

    // MARK: - シェイプ頂点のバインド

    // ユーザー頂点列を index 0 にバインドします。
    // Metal の setVertexBytes は 4096 バイト（Vertex3D 48B × 85 頂点）までしか
    // 受け付けないため、超過分は永続トリプルバッファ（shapeVertexBuffer）への
    // バンプ確保でバインドします（beginShape のポリゴンは 30 点程度で既に超過する）。
    // バインドできなかった場合は false を返すので、呼び出し側は描画を中止すること。
    //
    // `Vertex3D`（positionNormalColor）と `Vertex3DTextured`（positionNormalUV）は
    // どちらも 48B stride のため、同じリングをバイト単位で共有します
    // （`Canvas3DShapeUVTests` が stride 一致を固定）。
    private func bindShapeVertices<V>(_ vertices: [V], on encoder: MTLRenderCommandEncoder) -> Bool {
        assert(MemoryLayout<V>.stride == MemoryLayout<Vertex3D>.stride,
               "shapeVertexBuffer は 48B stride の頂点型のみ共有できる")
        let length = MemoryLayout<V>.stride * vertices.count
        if length <= 4096 {
            vertices.withUnsafeBytes { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: length, index: 0)
            }
            return true
        }
        // 書き込み開始位置を 16 頂点（= 768B）境界へ切り上げ、macOS の
        // setVertexBuffer offset 制約（256B アライン）を満たす。
        // Vertex3D は 48B stride のため 16 頂点が 256 の最小公倍境界。
        let alignedUsed = (shapeVertexBufferUsed + 15) & ~15
        if shapeVertexBuffer.ensureCapacity(
            alignedUsed + vertices.count,
            activeIndex: shapeVertexBufferIndex,
            usedCount: shapeVertexBufferUsed
        ) {
            let dst = UnsafeMutableRawPointer(shapeVertexBuffer.pointer(for: shapeVertexBufferIndex) + alignedUsed)
            vertices.withUnsafeBytes { src in
                dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
            encoder.setVertexBuffer(
                shapeVertexBuffer.buffer(for: shapeVertexBufferIndex),
                offset: alignedUsed * MemoryLayout<Vertex3D>.stride,
                index: 0
            )
            shapeVertexBufferUsed = alignedUsed + vertices.count
            return true
        }
        // リングの maxCapacity を超えるフレームのみ、従来の使い捨てバッファへ
        // フォールバック（機能は保つ）
        guard let buffer = vertices.withUnsafeBytes({ src in
            device.makeBuffer(bytes: src.baseAddress!, length: length, options: .storageModeShared)
        }) else {
            return false
        }
        // コマンドバッファが完了まで buffer を保持するため、ここで参照を手放してよい
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        return true
    }

    // テッセレーション済み 3D 頂点配列を塗りつぶし・ワイヤーフレームパスで描画
    func drawShape3DVertices(_ vertices: [Vertex3D]) {
        guard !vertices.isEmpty else { return }
        guard hasFill || hasStroke else { return }

        // テッセレーション済み頂点を一時 Mesh 化して drawMesh へ渡す
        // （記録経路 #152 / カスタムマテリアル #826。判定は shouldRouteShapeThroughMesh）
        if shouldRouteShapeThroughMesh {
            if let mesh = try? Mesh(device: device, vertices: vertices, indices: nil) {
                drawBakedShapeMesh(mesh)
            }
            return
        }

        guard let encoder = encoder else { return }

        ensureSkyboxDrawn()

        // beginShape/endShape は個別頂点描画を使用するため、インスタンスバッチをフラッシュ
        flushInstanceBatch()

        // 頂点バインディングはパイプライン切替をまたいで保持されるため、
        // fill / stroke パスの前に一度だけバインドする
        guard bindShapeVertices(vertices, on: encoder) else { return }

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if hasFill {
            encoder.setRenderPipelineState(pipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            // 頂点カラーへ焼き込み済みなので tint は白（#825）
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: Canvas3D.bakedShapeTint,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 0
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

            bindShadowResources(on: encoder)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        if hasStroke {
            encoder.setTriangleFillMode(.lines)
            // 頂点カラーには記録時の fill 色が焼き込まれているため、通常の
            // パイプラインでは線が「fill 色 × stroke 色」になる（#429）
            encoder.setRenderPipelineState(wirePipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

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

            bindShadowResources(on: encoder, enabled: false)

            Canvas3D.beginStrokeDepthBias(on: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            Canvas3D.endStrokeDepthBias(on: encoder)
            encoder.setTriangleFillMode(.fill)
        }
    }

    // テッセレーション済みの UV 付き 3D 頂点を、テクスチャを貼って描画する。
    // `vertices`（positionNormalColor）は stroke パスと記録経路の Mesh 本体、
    // `uvVertices`（positionNormalUV）は fill パスのテクスチャサンプリングに使う。
    func drawShape3DTexturedVertices(_ vertices: [Vertex3D], uvVertices: [Vertex3DTextured]) {
        guard !vertices.isEmpty else { return }
        guard hasFill || hasStroke else { return }

        // UV つきの一時 Mesh 化で drawMesh に載せる。`Mesh.hasUVs` が立つため
        // drawMesh 側がテクスチャ付きと判定し、シャドウにも落ちる
        // （テクスチャなしの経路と同じ構造・#152 / #826）
        if shouldRouteShapeThroughMesh {
            if let mesh = try? Mesh(device: device, vertices: vertices, indices: nil, uvVertices: uvVertices) {
                drawMesh(mesh)
            }
            return
        }

        guard let encoder = encoder else { return }

        ensureSkyboxDrawn()
        flushInstanceBatch()

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if hasFill {
            guard bindShapeVertices(uvVertices, on: encoder) else { return }

            encoder.setRenderPipelineState(texturedPipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 1
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

            bindShadowResources(on: encoder)

            if let tex = currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: uvVertices.count)
        }

        if hasStroke {
            // stroke は頂点カラーを無視して stroke 色だけで描く（#429）。
            // wirePipelineState は positionNormalColor なので UV なしの頂点列を貼り直す
            guard bindShapeVertices(vertices, on: encoder) else { return }

            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(wirePipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

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

            bindShadowResources(on: encoder, enabled: false)

            Canvas3D.beginStrokeDepthBias(on: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            Canvas3D.endStrokeDepthBias(on: encoder)
            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - ストロークの深度バイアス

    // ワイヤーフレーム（stroke）は塗りつぶしと同一のジオメトリを線として描き直す。
    // 深度比較が `.less` のため、等しい深度になる線は塗りに負けて 1 本も残らない（#429）。
    // 線をわずかに手前へずらして必ず勝たせる。1e-4 は正規化デバイス深度に対する
    // 値で、手前の別ジオメトリを貫通するほど大きくはない。
    private static let strokeDepthBias: Float = -1e-4

    static func beginStrokeDepthBias(on encoder: MTLRenderCommandEncoder) {
        encoder.setDepthBias(strokeDepthBias, slopeScale: -1, clamp: 0)
    }

    static func endStrokeDepthBias(on encoder: MTLRenderCommandEncoder) {
        encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
    }

    // 各頂点を小さな三角形として描画し、ポイントをシミュレート
    func drawShape3DPoints() {
        guard !shapeVertices3D.isEmpty else { return }

        // すべての頂点の三角形を単一バッチで構築
        var allVerts: [Vertex3D] = []
        allVerts.reserveCapacity(shapeVertices3D.count * 3)

        let s: Float = 0.5
        for v in shapeVertices3D {
            allVerts.append(Vertex3D(position: v.position + SIMD3(-s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( 0,  s, 0), normal: v.normal, color: v.color))
        }

        // 一時 Mesh 化して drawMesh へ渡す（記録経路 #152 / カスタムマテリアル #826）
        if shouldRouteShapeThroughMesh {
            if let mesh = try? Mesh(device: device, vertices: allVerts, indices: nil) {
                drawBakedShapeMesh(mesh)
            }
            return
        }

        guard let encoder = encoder else { return }

        ensureSkyboxDrawn()

        // 他の endShape パスと同様、先に保留中のインスタンスバッチを確定して
        // 描画順序を保つ（これがないとポイントがバッチ済みシェイプより先に
        // エンコードされる）
        flushInstanceBatch()

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        // 点ごとの色は頂点カラーが運ぶ。ここに先頭頂点の色を入れると
        // 「頂点[i] の色 × 頂点[0] の色」になり、点ごとの色分けが壊れる（#825）
        var uniforms = Canvas3DUniforms(
            modelMatrix: currentTransform,
            viewProjectionMatrix: viewProj,
            normalMatrix: normalMatrix,
            color: Canvas3D.bakedShapeTint,
            cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
            time: currentTime,
            lightCount: 0,
            hasTexture: 0
        )

        guard bindShapeVertices(allVerts, on: encoder) else { return }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

        var dummy = Light3D.zero
        encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
        var mat = currentMaterial
        encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

        // ポイントはライティングなし（lightCount=0）なのでシャドウ無効
        bindShadowResources(on: encoder, enabled: false)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: allVerts.count)
    }
}
