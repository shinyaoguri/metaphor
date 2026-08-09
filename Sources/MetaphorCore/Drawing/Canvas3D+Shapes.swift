import Metal
import simd

// beginShape/endShape の頂点記録とテッセレーション。
// テッセレーション済み頂点の GPU エンコードは Canvas3D+ShapeDrawing.swift が担う。
extension Canvas3D {
    // MARK: - 3D カスタムシェイプ (beginShape / endShape)

    /// 3D カスタムシェイプの頂点記録を開始します。
    ///
    /// - Parameter mode: シェイプのテッセレーションモード。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape3D = true
        shapeMode3D = mode
        shapeVertices3D.removeAll(keepingCapacity: true)
        shapeUVs3D.removeAll(keepingCapacity: true)
        shapeHasExplicitUV = false
        pendingNormal = nil
    }

    /// 指定位置に 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - z: z座標。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecordingShape3D else { return }
        appendShapeVertex3D(position: SIMD3(x, y, z), color: fillColor, uv: .zero)
    }

    /// 頂点カラー付きの 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - z: z座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        guard isRecordingShape3D else { return }
        appendShapeVertex3D(position: SIMD3(x, y, z), color: color.simd, uv: .zero)
    }

    /// テクスチャ座標付きの 3D 頂点を追加します。
    ///
    /// `texture(_:)` で画像を設定したシェイプでのみ効果があります。テクスチャ未設定の場合は
    /// UV が無視され、通常の fill で塗られます。
    ///
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - z: z座標。
    ///   - u: 水平テクスチャ座標（0.0〜1.0 に正規化）。
    ///   - v: 垂直テクスチャ座標（0.0〜1.0 に正規化）。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        guard isRecordingShape3D else { return }
        shapeHasExplicitUV = true
        appendShapeVertex3D(position: SIMD3(x, y, z), color: fillColor, uv: SIMD2(u, v))
    }

    // 頂点と UV を対で積む。両配列の添字対応はテッセレーション（インデックス列）が前提にする。
    private func appendShapeVertex3D(position: SIMD3<Float>, color: SIMD4<Float>, uv: SIMD2<Float>) {
        shapeVertices3D.append(Vertex3D(
            position: position,
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: color
        ))
        shapeUVs3D.append(uv)
    }

    /// 以降の頂点に適用する法線ベクトルを設定します。
    ///
    /// - Parameters:
    ///   - nx: 法線のx成分。
    ///   - ny: 法線のy成分。
    ///   - nz: 法線のz成分。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal = SIMD3(nx, ny, nz)
    }

    /// 記録を終了して 3D シェイプを描画します。
    ///
    /// - Parameter close: シェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape3D else { return }
        isRecordingShape3D = false

        guard !shapeVertices3D.isEmpty else { return }

        // polygon/triangles モードで法線が明示的に設定されていない場合、自動計算
        if pendingNormal == nil {
            autoComputeNormals()
        }

        switch shapeMode3D {
        case .polygon:
            drawShape3DPolygon(close: close)
        case .triangles:
            drawShape3DTriangles()
        case .triangleStrip:
            drawShape3DTriangleStrip()
        case .triangleFan:
            drawShape3DTriangleFan()
        case .points:
            drawShape3DPoints()
        case .lines:
            drawShape3DLines()
        }

        pendingNormal = nil
    }

    // MARK: - プライベート: 3D シェイプテッセレーション

    // 3頂点ごとに面法線を計算
    private func autoComputeNormals() {
        var i = 0
        while i + 2 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let p2 = shapeVertices3D[i + 2].position
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            let n = simd_normalize(simd_cross(edge1, edge2))
            let safeN = n.x.isNaN ? SIMD3<Float>(0, 1, 0) : n
            shapeVertices3D[i].normal = safeN
            shapeVertices3D[i + 1].normal = safeN
            shapeVertices3D[i + 2].normal = safeN
            i += 3
        }
    }

    // 単純な三角形ファンでポリゴンをテッセレーション（凸ポリゴン向け）
    private func drawShape3DPolygon(close: CloseMode) {
        guard shapeVertices3D.count >= 3 else { return }

        // 最初の3頂点から面法線を計算し、明示的な法線がない場合は全頂点へ適用
        if pendingNormal == nil {
            let p0 = shapeVertices3D[0].position
            let p1 = shapeVertices3D[1].position
            let p2 = shapeVertices3D[2].position
            let faceNormal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
            let safeNormal = faceNormal.x.isNaN ? SIMD3<Float>(0, 1, 0) : faceNormal
            for i in shapeVertices3D.indices {
                shapeVertices3D[i].normal = safeNormal
            }
        }

        var indices: [Int] = []
        indices.reserveCapacity((shapeVertices3D.count - 2) * 3)
        for i in 1..<(shapeVertices3D.count - 1) {
            indices.append(0)
            indices.append(i)
            indices.append(i + 1)
        }

        drawShape3DIndexed(indices)
    }

    // 独立した三角形として頂点を直接描画（3頂点ごとに1つの三角形）
    private func drawShape3DTriangles() {
        let count = (shapeVertices3D.count / 3) * 3
        guard count >= 3 else { return }
        drawShape3DIndexed(Array(0..<count))
    }

    // 三角形ストリップを独立した三角形にテッセレーション
    private func drawShape3DTriangleStrip() {
        guard shapeVertices3D.count >= 3 else { return }
        var indices: [Int] = []
        indices.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 0..<(shapeVertices3D.count - 2) {
            if i % 2 == 0 {
                indices.append(contentsOf: [i, i + 1, i + 2])
            } else {
                indices.append(contentsOf: [i + 1, i, i + 2])
            }
        }
        drawShape3DIndexed(indices)
    }

    // 三角形ファンを独立した三角形にテッセレーション
    private func drawShape3DTriangleFan() {
        guard shapeVertices3D.count >= 3 else { return }
        var indices: [Int] = []
        indices.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 1..<(shapeVertices3D.count - 1) {
            indices.append(contentsOf: [0, i, i + 1])
        }
        drawShape3DIndexed(indices)
    }

    // テッセレーション済みのインデックス列を頂点列へ展開して描画する。
    // 三角形化を「元頂点の並べ替え」として表現することで、位置・法線・カラーと
    // UV（`shapeUVs3D`）が同じ添字で必ず一緒に運ばれる。
    private func drawShape3DIndexed(_ indices: [Int]) {
        guard !indices.isEmpty else { return }

        // UV を宣言していても texture() 未設定なら通常の fill 経路（Processing 互換）
        guard shapeHasExplicitUV, currentTexture != nil else {
            var vertices: [Vertex3D] = []
            vertices.reserveCapacity(indices.count)
            for i in indices { vertices.append(shapeVertices3D[i]) }
            drawShape3DVertices(vertices)
            return
        }

        var vertices: [Vertex3D] = []
        var uvVertices: [Vertex3DTextured] = []
        vertices.reserveCapacity(indices.count)
        uvVertices.reserveCapacity(indices.count)
        for i in indices {
            let v = shapeVertices3D[i]
            vertices.append(v)
            uvVertices.append(Vertex3DTextured(position: v.position, normal: v.normal, uv: shapeUVs3D[i]))
        }
        drawShape3DTexturedVertices(vertices, uvVertices: uvVertices)
    }

    // 線分を細い三角形ペアとして描画（セグメントあたり2頂点）
    private func drawShape3DLines() {
        guard shapeVertices3D.count >= 2 else { return }
        var lineVerts: [Vertex3D] = []
        lineVerts.reserveCapacity((shapeVertices3D.count / 2) * 6)

        let lineWidth: Float = 0.5
        var i = 0
        while i + 1 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let dir = p1 - p0
            let len = simd_length(dir)
            guard len > 0 else { i += 2; continue }

            // 線方向とビュー方向の外積を使用してオフセットを計算
            let viewDir = simd_normalize(cameraEye - (p0 + p1) * 0.5)
            var offset = simd_normalize(simd_cross(dir, viewDir)) * lineWidth * 0.5
            if offset.x.isNaN { offset = SIMD3(0, lineWidth * 0.5, 0) }

            let n = shapeVertices3D[i].normal
            let c = shapeVertices3D[i].color

            lineVerts.append(Vertex3D(position: p0 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            i += 2
        }

        drawShape3DVertices(lineVerts)
    }
}
