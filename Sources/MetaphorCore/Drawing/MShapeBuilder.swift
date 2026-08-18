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
        usedExplicitNormal3D = false
        isInContour = false
        contourStartIndex = 0
        usedContourWhileRecording = false
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
    ///
    /// 直近の `normal(_:_:_:)` の値を焼き込みます（`endShape()` まで持続。#876）。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(position: SIMD3(x, y, z), normal: normal))
    }

    /// テクスチャ座標付きの3D頂点を追加します。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(
            position: SIMD3(x, y, z), normal: normal, uv: SIMD2(u, v)))
    }

    /// 以降の 3D 頂点に適用する法線ベクトルを設定します。
    ///
    /// 次に `beginShape()` を呼ぶか `endShape()` で記録を閉じるまで持続します。
    /// イミディエイトの ``Canvas3D/normal(_:_:_:)`` と同じ範囲で、Processing の
    /// `PShape.normal()` とも同じです（#876。以前は**次の 1 頂点だけ**でした）。
    /// 頂点ごとに違う法線を入れたいなら、これまでどおり頂点ごとに呼び直します。
    /// - Note: 一度でも呼ぶと**そのシェイプ全体で**面法線の自動計算が止まります（#738）。
    ///   最初の `normal()` より前に積んだ頂点は既定の (0, 1, 0) のままになります。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal3D = SIMD3(nx, ny, nz)
        usedExplicitNormal3D = true
    }

    // MARK: - コンター（2D穴）

    /// 2Dシェイプ内のコンター（穴）の記録を開始します（2D シェイプ専用）。
    ///
    /// この呼び出しから `endContour()` までに追加された頂点が穴の境界を定義します。
    /// 3D シェイプ（`vertex(x, y, z)` で組んだもの）では穴を開けられないため、
    /// 呼ばれても何もせず初回だけ警告します（#736）。
    public func beginContour() {
        guard isRecording else { return }
        usedContourWhileRecording = true
        if case .path3D = kind {
            warnContourIn3DOnce()
            return
        }
        isInContour = true
        contourStartIndex = vertices2D.count
    }

    /// 2Dシェイプ内のコンター（穴）の記録を終了します（2D シェイプ専用）。
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

    /// グレースケール値で塗りつぶし色を設定します。
    ///
    /// 値は ``Sketch/createShape()`` した時点の `colorMode()` のレンジで解釈されます
    /// （既定は 0-255）。スケッチ側の `fill(_:)` と同じ規則です。
    public func fill(_ gray: Float) {
        capturedStyle.fillColor = colorModeConfig.toGray(gray).simd
        capturedStyle.hasFill = true
    }

    /// グレースケール値と不透明度で塗りつぶし色を設定します。
    ///
    /// どちらの値も ``Sketch/createShape()`` した時点の `colorMode()` のレンジで
    /// 解釈されます（既定はどちらも 0-255）。
    public func fill(_ gray: Float, _ alpha: Float) {
        capturedStyle.fillColor = colorModeConfig.toGray(gray, alpha).simd
        capturedStyle.hasFill = true
    }

    /// 3 成分の値と、省略できる不透明度で塗りつぶし色を設定します。
    ///
    /// 値は ``Sketch/createShape()`` した時点の `colorMode()` の色空間とレンジで
    /// 解釈されます（既定は RGB 0-255）。スケッチ側の `fill(_:_:_:_:)` と同じ規則なので、
    /// `colorMode(.hsb, 360, 100, 100)` の下では `fill(180, 100, 100)` がシアンになります。
    ///
    /// - Parameters:
    ///   - v1: 1 番目の成分（赤または色相）。
    ///   - v2: 2 番目の成分（緑または彩度）。
    ///   - v3: 3 番目の成分（青または明度）。
    ///   - a: 不透明度。省略すると不透明（アルファの最大値）になります。
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        capturedStyle.fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
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

    /// グレースケール値でストローク色を設定します。
    ///
    /// 値は ``Sketch/createShape()`` した時点の `colorMode()` のレンジで解釈されます
    /// （既定は 0-255）。スケッチ側の `stroke(_:)` と同じ規則です。
    public func stroke(_ gray: Float) {
        capturedStyle.strokeColor = colorModeConfig.toGray(gray).simd
        capturedStyle.hasStroke = true
    }

    /// グレースケール値と不透明度でストローク色を設定します。
    ///
    /// どちらの値も ``Sketch/createShape()`` した時点の `colorMode()` のレンジで
    /// 解釈されます（既定はどちらも 0-255）。
    public func stroke(_ gray: Float, _ alpha: Float) {
        capturedStyle.strokeColor = colorModeConfig.toGray(gray, alpha).simd
        capturedStyle.hasStroke = true
    }

    /// 3 成分の値と、省略できる不透明度でストローク色を設定します。
    ///
    /// 値は ``Sketch/createShape()`` した時点の `colorMode()` の色空間とレンジで
    /// 解釈されます（既定は RGB 0-255）。スケッチ側の `stroke(_:_:_:_:)` と同じ規則なので、
    /// `colorMode(.hsb, 360, 100, 100)` の下では `stroke(180, 100, 100)` がシアンになります。
    ///
    /// - Parameters:
    ///   - v1: 1 番目の成分（赤または色相）。
    ///   - v2: 2 番目の成分（緑または彩度）。
    ///   - v3: 3 番目の成分（青または明度）。
    ///   - a: 不透明度。省略すると不透明（アルファの最大値）になります。
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        capturedStyle.strokeColor = colorModeConfig.toColor(v1, v2, v3, a).simd
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
    /// - Note: 自己交差する頂点列（五芒星など）の塗りは **nonzero winding** 規則に従います
    ///   （即時モードの `endShape(_:)` と同じ）。巻き数が 0 でない領域が塗られるので、
    ///   五芒星は中央の五角形まで塗られたべた塗りの星になります。
    ///
    /// - Parameter close: 最後の頂点から最初の頂点に接続してシェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        guard isRecording else { return }
        isRecording = false

        if case .path2D = kind {
            closeMode2D = close
        } else if case .path3D = kind {
            closeMode3D = close
            // beginContour() が最初の頂点より先に来ると、その時点では kind がまだ
            // .path3D になっていない。ここで改めて拾って取りこぼさない（#736）
            if usedContourWhileRecording {
                warnContourIn3DOnce()
            }
        }

        // `normal()` の持続はこのシェイプの中だけ（イミディエイトの
        // `Canvas3D.endShape()` と同じ位置で畳む。#876）。
        pendingNormal3D = nil

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
            // 穴なし。自己交差があれば nonzero winding で塗り分ける（#886）。
            // 交点ぶん頂点が増えるので、インデックスは返ってきた頂点配列に当てる。
            let tess = EarClipTriangulator.triangulateNonZero(outerPoints)
            cachedTriangles2D = buildTrianglesFromIndices(tess.indices, points: tess.vertices)
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
    ///
    /// 塗りとストロークで別のメッシュを持ちます（#735）。理由は
    /// ``MShape/cachedStrokeMesh3D`` を参照。
    func buildMesh3D() {
        guard case .path3D = kind, !vertices3D.isEmpty else {
            cachedMesh3D = nil
            cachedStrokeMesh3D = nil
            isDirty = false
            return
        }

        cachedMesh3D = buildFillMesh3D()
        cachedStrokeMesh3D = buildStrokeMesh3D()
        isDirty = false
    }

    private func buildFillMesh3D() -> Mesh? {
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
        // （UInt32 で構築し、65,536 頂点超の大規模ジェネラティブでもトラップしない）
        var indices: [UInt32] = []
        switch shapeMode3D {
        case .polygon:
            // ポリゴンモードではファンテッセレーション
            if vertices3D.count >= 3 {
                for i in 1..<(vertices3D.count - 1) {
                    indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
                }
                if closeMode3D == .close && vertices3D.count >= 3 {
                    // ファンにより既に閉じている
                }
            }
        case .triangles:
            var i = 0
            while i + 2 < vertices3D.count {
                indices.append(contentsOf: [UInt32(i), UInt32(i + 1), UInt32(i + 2)])
                i += 3
            }
        case .triangleStrip:
            // 三角形 1 枚に足りない頂点数は `count - 2` が負になり、Range の生成でトラップする。
            // 塗る面が作れないだけなのでインデックスを空のままにする（2D 側の
            // `tessellateTriangleStrip2D()` と同じガード。#881）。
            guard vertices3D.count >= 3 else { break }
            for i in 0..<(vertices3D.count - 2) {
                if i % 2 == 0 {
                    indices.append(contentsOf: [UInt32(i), UInt32(i + 1), UInt32(i + 2)])
                } else {
                    indices.append(contentsOf: [UInt32(i + 1), UInt32(i), UInt32(i + 2)])
                }
            }
        case .triangleFan:
            // 同上（2D 側の `tessellateTriangleFan2D()` と同じガード。#881）。
            guard vertices3D.count >= 3 else { break }
            for i in 1..<(vertices3D.count - 1) {
                indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
            }
        case .lines, .points:
            // 塗る面は無い。線分・点は buildStrokeMesh3D() が持つ
            break
        }

        guard !indices.isEmpty else { return nil }

        // `normal()` を一度も呼んでいないシェイプは、全頂点が既定の (0, 1, 0) のままで
        // 真横からのライトに真っ黒に沈む。組み上がったインデックス列から面法線を
        // 入れ直す（#738）。イミディエイト側が endShape() で自動計算するのと揃える。
        if !usedExplicitNormal3D {
            let normals = FaceNormals.compute(
                positions: vertices3D.map(\.position), indices: indices)
            for i in meshVertices.indices {
                meshVertices[i].normal = normals[i]
            }
            if uvVertices != nil {
                for i in uvVertices!.indices {
                    uvVertices![i].normal = normals[i]
                }
            }
        }

        if meshVertices.count <= 65535 {
            return try? Mesh(
                device: device,
                vertices: meshVertices,
                indices: indices.map { UInt16($0) },
                uvVertices: uvVertices
            )
        }
        return try? Mesh(
            device: device,
            vertices: meshVertices,
            indices32: indices,
            uvVertices: uvVertices
        )
    }

    /// ストローク用メッシュを構築します。線分は退化三角形 `(a, b, b)` で表します。
    ///
    /// ワイヤーフレーム描画は三角形の 3 辺を線で描くので、`a-b` / `b-b`（点）/ `b-a` となり
    /// 線分 `a-b` だけが残ります。これにより新しいパイプラインを足さずに、既存のストローク経路
    /// （ライティング無し・`strokeColor` 単色・depth bias・インスタンシング・コマンド記録）を
    /// そのまま使えます。
    ///
    /// 三角形系モードは塗りメッシュ自身のワイヤーフレームが正しい辺を描くため nil を返します。
    private func buildStrokeMesh3D() -> Mesh? {
        // 位置以外は使われない（ストロークの色はワイヤーパイプラインの strokeColor が決め、
        // ライティングも掛からない）ので、法線と色は既定値で埋める。
        let normal = SIMD3<Float>(0, 1, 0)
        let white = SIMD4<Float>(1, 1, 1, 1)
        var verts: [Vertex3D] = []

        func appendSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
            verts.append(Vertex3D(position: a, normal: normal, color: white))
            verts.append(Vertex3D(position: b, normal: normal, color: white))
            verts.append(Vertex3D(position: b, normal: normal, color: white))
        }

        switch shapeMode3D {
        case .polygon:
            guard vertices3D.count >= 2 else { return nil }
            verts.reserveCapacity(vertices3D.count * 3)
            for i in 0..<(vertices3D.count - 1) {
                appendSegment(vertices3D[i].position, vertices3D[i + 1].position)
            }
            if closeMode3D == .close {
                appendSegment(vertices3D[vertices3D.count - 1].position, vertices3D[0].position)
            }

        case .lines:
            verts.reserveCapacity((vertices3D.count / 2) * 3)
            var i = 0
            while i + 1 < vertices3D.count {
                appendSegment(vertices3D[i].position, vertices3D[i + 1].position)
                i += 2
            }

        case .points:
            // 点は線分にできないので、イミディエイトの `drawShape3DPoints()` と同じ小三角形を置く
            let s: Float = 0.5
            verts.reserveCapacity(vertices3D.count * 3)
            for v in vertices3D {
                verts.append(Vertex3D(position: v.position + SIMD3(-s, -s, 0), normal: normal, color: white))
                verts.append(Vertex3D(position: v.position + SIMD3(s, -s, 0), normal: normal, color: white))
                verts.append(Vertex3D(position: v.position + SIMD3(0, s, 0), normal: normal, color: white))
            }

        case .triangles, .triangleStrip, .triangleFan:
            return nil
        }

        guard !verts.isEmpty else { return nil }
        return try? Mesh(device: device, vertices: verts, indices: nil)
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
