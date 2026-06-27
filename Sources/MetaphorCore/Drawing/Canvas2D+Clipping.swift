import Metal
import simd

extension Canvas2D {
    // MARK: - クリッピング

    /// 指定した矩形に後続の描画をクリッピングします。
    ///
    /// Metal のシザーテストによるハードウェアアクセラレーテッドクリッピングを使用します。
    /// ``endClip()`` を呼び出して前のクリップ領域を復元します。
    /// スタックによるネストされたクリップに対応しています。
    ///
    /// - Parameters:
    ///   - x: クリップ領域のx座標。
    ///   - y: クリップ領域のy座標。
    ///   - w: クリップ領域の幅。
    ///   - h: クリップ領域の高さ。
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        flush()
        clipStack.append(clipRect)
        // 要求矩形とキャンバス矩形の交差を取る。
        // 負の原点では幅・高さも削る必要があり、キャンバス外の矩形は
        // 空のシザーに潰す（範囲外のシザー矩形は Metal validation で
        // クラッシュするため、原点もキャンバス内にクランプする）。
        let x0 = min(max(0, Int(x)), Int(width))
        let y0 = min(max(0, Int(y)), Int(height))
        let x1 = min(max(x0, Int(x) + Int(w)), Int(width))
        let y1 = min(max(y0, Int(y) + Int(h)), Int(height))
        clipRect = MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        encoder?.setScissorRect(clipRect!)
    }

    /// 現在のクリップ領域を終了し、前のクリップ領域を復元します。
    public func endClip() {
        flush()
        clipRect = clipStack.popLast() ?? nil
        if let rect = clipRect {
            encoder?.setScissorRect(rect)
        } else {
            // フルビューポートを復元
            let fullRect = MTLScissorRect(x: 0, y: 0, width: Int(width), height: Int(height))
            encoder?.setScissorRect(fullRect)
        }
    }

    /// カラー、テクスチャ、インスタンスを含むすべての保留中の描画バッチをフラッシュします。
    public func flush() {
        flushInstancedBatch()
        flushColorVertices()
        flushTexturedVertices()
    }

    // カラー頂点バッチのみをフラッシュ
    func flushColorVertices() {
        guard let encoder = encoder, vertexCount > 0 else { return }

        guard let pipeline = pipelineStates[currentBlendMode] else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: bufferOffset, vertexCount: vertexCount)
        bufferOffset += vertexCount
        vertexCount = 0
    }

    // テクスチャ頂点バッチのみをフラッシュ
    func flushTexturedVertices() {
        guard let encoder = encoder, texturedVertexCount > 0 else { return }
        guard let texPipeline = texturedPipelineStates[currentBlendMode] else { return }
        guard let texture = currentBoundTexture else { return }

        encoder.setRenderPipelineState(texPipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(texturedVertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: texturedBufferOffset, vertexCount: texturedVertexCount)
        texturedBufferOffset += texturedVertexCount
        texturedVertexCount = 0
    }
}
