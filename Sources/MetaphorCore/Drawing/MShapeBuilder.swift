import Metal
import simd

// MARK: - シェイプ構築 API (beginShape / vertex / endShape)

extension MShape {

    // MARK: - beginShape

    /// カスタムシェイプの頂点記録を開始します。
    ///
    /// `vertex()` で頂点を追加し、`endShape()` で確定します。
    /// 必要に応じて `beginContour()`/`endContour()` で穴を定義できます（2Dのみ）。
    ///
    /// - Parameter mode: プリミティブ描画モード（デフォルト: `.polygon`）。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecording = true
        vertices2D.removeAll(keepingCapacity: true)
        vertices3D.removeAll(keepingCapacity: true)
        contourRanges.removeAll(keepingCapacity: true)
        pendingNormal3D = nil
        isInContour = false
        contourStartIndex = 0
        shapeMode2D = mode
        shapeMode3D = mode
        invalidateCache()
    }

    // MARK: - 2D 頂点

    /// 記録中のシェイプに2D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y)))
    }

    /// 頂点カラー付きの2D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y), color: color.simd))
    }

    /// テクスチャ座標付きの2D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y), uv: SIMD2(u, v)))
    }

    // MARK: - 3D 頂点

    /// 記録中のシェイプに3D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(position: SIMD3(x, y, z), normal: normal))
        pendingNormal3D = nil
    }

    /// テクスチャ座標付きの3D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(
            position: SIMD3(x, y, z), normal: normal, uv: SIMD2(u, v)))
        pendingNormal3D = nil
    }

    /// 次の3D頂点に適用する法線ベクトルを設定します。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal3D = SIMD3(nx, ny, nz)
    }

    // MARK: - コンター（2D穴）

    /// 2Dシェイプ内のコンター（穴）の記録を開始します。
    ///
    /// この呼び出しから `endContour()` までに追加された頂点が穴の境界を定義します。
    public func beginContour() {
        guard isRecording else { return }
        isInContour = true
        contourStartIndex = vertices2D.count
    }

    /// 2Dシェイプ内のコンター（穴）の記録を終了します。
    public func endContour() {
        guard isRecording, isInContour else { return }
        isInContour = false
        let endIndex = vertices2D.count
        if endIndex > contourStartIndex {
            contourRanges.append(contourStartIndex..<endIndex)
        }
    }

    // MARK: - 定義時のスタイル設定

    /// シェイプ定義中に塗りつぶし色を設定します。
    public func fill(_ color: Color) {
        capturedStyle.fillColor = color.simd
        capturedStyle.hasFill = true
    }

    /// グレースケール値（0-255）で塗りつぶし色を設定します。
    public func fill(_ gray: Float) {
        let v = gray / 255.0
        capturedStyle.fillColor = SIMD4(v, v, v, 1)
        capturedStyle.hasFill = true
    }

    /// 塗りつぶしを無効にします。
    public func noFill() {
        capturedStyle.hasFill = false
    }

    /// シェイプ定義中にストローク色を設定します。
    public func stroke(_ color: Color) {
        capturedStyle.strokeColor = color.simd
        capturedStyle.hasStroke = true
    }

    /// グレースケール値（0-255）でストローク色を設定します。
    public func stroke(_ gray: Float) {
        let v = gray / 255.0
        capturedStyle.strokeColor = SIMD4(v, v, v, 1)
        capturedStyle.hasStroke = true
    }

    /// ストロークを無効にします。
    public func noStroke() {
        capturedStyle.hasStroke = false
    }

    /// シェイプ定義中にストロークの太さを設定します。
    public func strokeWeight(_ weight: Float) {
        capturedStyle.strokeWeight = weight
    }

    // MARK: - endShape

    /// シェイプを確定し、記録された頂点からジオメトリを構築します。
    ///
    /// - Parameter close: 最後の頂点から最初の頂点に接続してシェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        guard isRecording else { return }
        isRecording = false

        if case .path2D = kind {
            closeMode2D = close
        } else if case .path3D = kind {
            closeMode3D = close
        }

        // ジオメトリは最初の描画時に遅延構築される
        isDirty = true
    }
}

// MARK: - テッセレーション / メッシュ構築

extension MShape {

    /// 2Dカスタムシェイプをテッセレーションし、結果をキャッシュします。
    ///
    /// ポリゴンモードでは `EarClipTriangulator` を使用します。
    /// `isDirty` が true またはキャッシュが nil の場合のみ呼び出してください。
    func tessellate2D() {
        guard case .path2D = kind, !vertices2D.isEmpty else {
            cachedTriangles2D = []
            cachedStrokeOutline2D = []
            isDirty = false
            return
        }

        // 外側ポリゴンを抽出（コンター範囲に含まれない頂点）
        let outerEnd = contourRanges.first?.lowerBound ?? vertices2D.count
        let outerPoints = vertices2D[0..<outerEnd].map { ($0.position.x, $0.position.y) }

        switch shapeMode2D {
        case .polygon:
            tessellatePolygon2D(outerPoints: outerPoints)

        case .triangles:
            tessellateTriangles2D()

        case .triangleStrip:
            tessellateTriangleStrip2D()

        case .triangleFan:
            tessellateTriangleFan2D()

        case .lines, .points:
            // lines/points モードでは塗りつぶしテッセレーション不要
            cachedTriangles2D = []
        }

        // ストロークアウトラインの構築
        cachedStrokeOutline2D = outerPoints
        isDirty = false
    }

    private func tessellatePolygon2D(outerPoints: [(Float, Float)]) {
        guard outerPoints.count >= 3 else {
            cachedTriangles2D = []
            return
        }

        if contourRanges.isEmpty {
            // 穴なしの単純ポリゴン
            let indices = EarClipTriangulator.triangulate(outerPoints)
            cachedTriangles2D = buildTrianglesFromIndices(indices, points: outerPoints)
        } else {
            // 穴ありポリゴン
            let holes: [[(Float, Float)]] = contourRanges.map { range in
                vertices2D[range].map { ($0.position.x, $0.position.y) }
            }
            let result = EarClipTriangulator.triangulateWithHoles(outer: outerPoints, holes: holes)
            cachedTriangles2D = buildTrianglesFromIndices(result.indices, points: result.vertices)
        }
    }

    private func tessellateTriangles2D() {
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        var i = 0
        while i + 2 < vertices2D.count {
            tris.append((
                vertices2D[i].position,
                vertices2D[i + 1].position,
                vertices2D[i + 2].position
            ))
            i += 3
        }
        cachedTriangles2D = tris
    }

    private func tessellateTriangleStrip2D() {
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        guard vertices2D.count >= 3 else { cachedTriangles2D = []; return }
        for i in 0..<(vertices2D.count - 2) {
            if i % 2 == 0 {
                tris.append((
                    vertices2D[i].position,
                    vertices2D[i + 1].position,
                    vertices2D[i + 2].position
                ))
            } else {
                tris.append((
                    vertices2D[i + 1].position,
                    vertices2D[i].position,
                    vertices2D[i + 2].position
                ))
            }
        }
        cachedTriangles2D = tris
    }

    private func tessellateTriangleFan2D() {
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        guard vertices2D.count >= 3 else { cachedTriangles2D = []; return }
        let center = vertices2D[0].position
        for i in 1..<(vertices2D.count - 1) {
            tris.append((center, vertices2D[i].position, vertices2D[i + 1].position))
        }
        cachedTriangles2D = tris
    }

    private func buildTrianglesFromIndices(
        _ indices: [Int], points: [(Float, Float)]
    ) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        tris.reserveCapacity(indices.count / 3)
        var i = 0
        while i + 2 < indices.count {
            let p0 = points[indices[i]]
            let p1 = points[indices[i + 1]]
            let p2 = points[indices[i + 2]]
            tris.append((
                SIMD2(p0.0, p0.1),
                SIMD2(p1.0, p1.1),
                SIMD2(p2.0, p2.1)
            ))
            i += 3
        }
        return tris
    }

    /// 3Dカスタムシェイプの頂点から Mesh を構築し、結果をキャッシュします。
    func buildMesh3D() {
        guard case .path3D = kind, !vertices3D.isEmpty else {
            cachedMesh3D = nil
            isDirty = false
            return
        }

        let hasUVs = vertices3D.contains { $0.uv != nil }
        let white = SIMD4<Float>(1, 1, 1, 1)

        // Vertex3D 配列の構築
        var meshVertices: [Vertex3D] = []
        meshVertices.reserveCapacity(vertices3D.count)
        var uvVertices: [Vertex3DTextured]? = hasUVs ? [] : nil
        uvVertices?.reserveCapacity(vertices3D.count)

        for sv in vertices3D {
            let color = sv.color ?? white
            meshVertices.append(Vertex3D(position: sv.position, normal: sv.normal, color: color))
            if hasUVs {
                uvVertices?.append(Vertex3DTextured(
                    position: sv.position, normal: sv.normal,
                    uv: sv.uv ?? SIMD2(0, 0)))
            }
        }

        // シェイプモードに基づくインデックス配列の構築
        var indices: [UInt16] = []
        switch shapeMode3D {
        case .polygon:
            // ポリゴンモードではファンテッセレーション
            if vertices3D.count >= 3 {
                for i in 1..<(vertices3D.count - 1) {
                    indices.append(contentsOf: [0, UInt16(i), UInt16(i + 1)])
                }
                if closeMode3D == .close && vertices3D.count >= 3 {
                    // ファンにより既に閉じている
                }
            }
        case .triangles:
            var i = 0
            while i + 2 < vertices3D.count {
                indices.append(contentsOf: [UInt16(i), UInt16(i + 1), UInt16(i + 2)])
                i += 3
            }
        case .triangleStrip:
            for i in 0..<(vertices3D.count - 2) {
                if i % 2 == 0 {
                    indices.append(contentsOf: [UInt16(i), UInt16(i + 1), UInt16(i + 2)])
                } else {
                    indices.append(contentsOf: [UInt16(i + 1), UInt16(i), UInt16(i + 2)])
                }
            }
        case .triangleFan:
            for i in 1..<(vertices3D.count - 1) {
                indices.append(contentsOf: [0, UInt16(i), UInt16(i + 1)])
            }
        case .lines, .points:
            // 描画時に別処理。塗りつぶしメッシュなし
            break
        }

        guard !indices.isEmpty else {
            cachedMesh3D = nil
            isDirty = false
            return
        }

        cachedMesh3D = try? Mesh(
            device: device,
            vertices: meshVertices,
            indices: indices,
            uvVertices: uvVertices
        )
        isDirty = false
    }

    /// ジオメトリキャッシュが最新であることを保証します。描画前に呼び出されます。
    func ensureCacheValid() {
        guard isDirty else { return }
        switch kind {
        case .path2D:
            tessellate2D()
        case .path3D:
            buildMesh3D()
        default:
            isDirty = false
        }
    }
}
