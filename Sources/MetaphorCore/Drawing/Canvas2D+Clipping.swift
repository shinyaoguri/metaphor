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
        // 遅延モードでは scissor 変更も呼び出し順を保ってコマンド化する（#71・宿題③）。
        // 影オフ即時モードでは encode 経由で従来どおり即座に setScissorRect する。
        emit(.setScissor(clipRect))
    }

    /// 現在のクリップ領域を終了し、前のクリップ領域を復元します。
    public func endClip() {
        flush()
        clipRect = clipStack.popLast() ?? nil
        // clipRect が nil のときは encode 側でフルビューポートへ復元する。
        emit(.setScissor(clipRect))
    }

    /// カラー、テクスチャ、インスタンスを含むすべての保留中の描画バッチをフラッシュします。
    public func flush() {
        flushInstancedBatch()
        flushColorVertices()
        flushTexturedVertices()
    }

    // カラー頂点バッチのみをフラッシュ（遅延モードでは明示コマンドとして積む。#70 / #71）
    func flushColorVertices() {
        guard vertexCount > 0 else { return }
        guard pipelineStates[currentBlendMode] != nil else { return }
        guard isDeferring || encoder != nil else { return }

        let vStart = bufferOffset
        let vCount = vertexCount
        bufferOffset += vertexCount
        vertexCount = 0

        emit(.colorBatch(blend: currentBlendMode, vertexStart: vStart, vertexCount: vCount))
    }

    // テクスチャ頂点バッチのみをフラッシュ（遅延モードでは明示コマンドとして積む。#70 / #71）
    func flushTexturedVertices() {
        guard texturedVertexCount > 0 else { return }
        guard texturedPipelineStates[currentBlendMode] != nil else { return }
        guard let texture = currentBoundTexture else { return }
        guard isDeferring || encoder != nil else { return }

        let vStart = texturedBufferOffset
        let vCount = texturedVertexCount
        texturedBufferOffset += texturedVertexCount
        texturedVertexCount = 0

        emit(.texturedBatch(
            blend: currentBlendMode, vertexStart: vStart, vertexCount: vCount, texture: texture))
    }
}
