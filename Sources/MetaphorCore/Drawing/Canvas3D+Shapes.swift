import Metal
import simd

// beginShape/endShape の頂点記録とテッセレーション。
// テッセレーション済み頂点の GPU エンコードは Canvas3D+ShapeDrawing.swift が担う。
extension Canvas3D {
    // MARK: - 3D カスタムシェイプ (beginShape / endShape)

    /// 3D カスタムシェイプの頂点記録を開始します。
    ///
    /// 頂点は記録時の色を焼き込んで積むため、記録の途中で色を変えると頂点ごとに色が
    /// 付きます。焼き込む色は面モード（`.polygon` / `.triangles` など）では fill、
    /// **`.lines` / `.points` では stroke** です（線・点の色を決めるのは `stroke()`。
    /// `noStroke()` のときは fill に戻ります, #739）。描画側は焼き込み済みを前提に
    /// tint を白で送ります（`Canvas3D.bakedShapeTint`。二重適用の防止, #825）。
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
        appendShapeVertex3D(position: SIMD3(x, y, z), color: bakedVertexColor, uv: .zero)
    }

    /// 頂点カラー付きの 3D 頂点を追加します。
    ///
    /// 与えた色は現在の fill に左右されず、そのまま出ます（#825）。
    /// `texture(_:)` を貼ったシェイプでは頂点カラーは使われません。
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
        appendShapeVertex3D(position: SIMD3(x, y, z), color: bakedVertexColor, uv: SIMD2(u, v))
    }

    // 色を明示しない頂点へ焼き込む色（#739）。
    //
    // `.lines` / `.points` は「線・点」なので、色を決めるのは `stroke()` — Processing の
    // LINES / POINTS と同じ語彙にする。`stroke()` を頂点の途中で変えれば線分ごと・点ごとに
    // 色が変わる。`vertex(x, y, z, color)` で明示した色はここを通らないので、
    // 頂点カラーは今までどおり勝つ（#825 の点ごとの色分けを保つ）。
    //
    // `noStroke()` のときは従来どおり fill 色。線・点しか無いシェイプを黙って消さないため
    // （`drawShape3DVertices` の `hasFill || hasStroke` ガードで、両方無ければ元から描かれない）。
    private var bakedVertexColor: SIMD4<Float> {
        switch shapeMode3D {
        case .lines, .points:
            return hasStroke ? strokeColor : fillColor
        default:
            return fillColor
        }
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

        // `normal()` を書かなかったシェイプの法線は、テッセレーション後の
        // `drawShape3DIndexed()` が組み上がったインデックス列から入れる（#875）。
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

    // 単純な三角形ファンでポリゴンをテッセレーション（凸ポリゴン向け）
    private func drawShape3DPolygon(close: CloseMode) {
        guard shapeVertices3D.count >= 3 else { return }

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
    //
    // `normal()` を書かなかったシェイプへ面法線を入れるのもここ（#875）。
    // 面モードはすべてここへ合流するので、規則が 1 箇所で済む。
    private func drawShape3DIndexed(_ indices: [Int]) {
        guard !indices.isEmpty else { return }

        applyAutoNormals(indices)

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

    // `normal()` を一度も書かなかったシェイプへ面法線を入れる（#875）。
    //
    // 規則はリテインド側（`MShapeBuilder.buildFillMesh3D()`）と同じ共有ヘルパー
    // `FaceNormals` 1 つだけ。組み上がったインデックス列を 1 三角形ずつ読むので、
    // `.polygon` / `.triangles` / `.triangleStrip` / `.triangleFan` が同じ経路で
    // 片付く。旧実装は「3 頂点ごと」（`i += 3`）で、ストリップ／ファンの topology に
    // 合わず後ろの頂点が既定値のまま取り残されていた。
    //
    // `.lines` / `.points` はここを通らない（面のインデックス列を持たない）ので、
    // 既定の (0, 1, 0) のまま。線・点に面法線は無いので、旧実装が入れていた
    // 「3 頂点ごとの面法線」という幾何的に無意味な値は引き継がない。
    private func applyAutoNormals(_ indices: [Int]) {
        guard pendingNormal == nil else { return }

        let normals = FaceNormals.compute(
            positions: shapeVertices3D.map(\.position),
            indices: indices.map { UInt32($0) })
        for i in shapeVertices3D.indices {
            shapeVertices3D[i].normal = normals[i]
        }
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
