import Metal
import simd

/// 2D形状をバッチ処理して効率的に描画するレンダラー
/// 形状を頂点バッファに蓄積し、flush()で一括描画する
public final class BatchRenderer {
    private let device: MTLDevice
    private let pipelines: PipelineCache

    // 頂点データ
    private var vertices: [ShapeVertex] = []
    private var indices: [UInt32] = []

    // Metalバッファ
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    // バッファ容量管理
    private var vertexCapacity: Int
    private var indexCapacity: Int
    private let initialVertexCapacity = 10000
    private let initialIndexCapacity = 20000

    // キャンバスサイズ（射影行列用）
    private var canvasWidth: Float = 1920
    private var canvasHeight: Float = 1080

    public init(device: MTLDevice, pipelines: PipelineCache) {
        self.device = device
        self.pipelines = pipelines
        self.vertexCapacity = initialVertexCapacity
        self.indexCapacity = initialIndexCapacity

        allocateBuffers()
    }

    /// キャンバスサイズを設定
    public func setCanvasSize(width: Float, height: Float) {
        self.canvasWidth = width
        self.canvasHeight = height
    }

    // MARK: - Buffer Management

    private func allocateBuffers() {
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<ShapeVertex>.stride * vertexCapacity,
            options: .storageModeShared
        )
        indexBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * indexCapacity,
            options: .storageModeShared
        )
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<ShapeUniforms>.stride,
            options: .storageModeShared
        )
    }

    private func ensureCapacity(vertices vertexCount: Int, indices indexCount: Int) {
        var needsReallocation = false

        if self.vertices.count + vertexCount > vertexCapacity {
            vertexCapacity = max(vertexCapacity * 2, self.vertices.count + vertexCount)
            needsReallocation = true
        }

        if self.indices.count + indexCount > indexCapacity {
            indexCapacity = max(indexCapacity * 2, self.indices.count + indexCount)
            needsReallocation = true
        }

        if needsReallocation {
            allocateBuffers()
        }
    }

    // MARK: - Shape Addition

    /// 四角形を追加（塗りつぶし）
    public func addRect(
        x: Float, y: Float, width: Float, height: Float,
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        ensureCapacity(vertices: 4, indices: 6)
        let baseIndex = UInt32(vertices.count)

        // 4つの頂点を変換
        let positions = [
            SIMD2<Float>(x, y),
            SIMD2<Float>(x + width, y),
            SIMD2<Float>(x + width, y + height),
            SIMD2<Float>(x, y + height)
        ]

        for (i, pos) in positions.enumerated() {
            let transformed = transform * SIMD4<Float>(pos.x, pos.y, 0, 1)
            vertices.append(ShapeVertex(
                position: SIMD2<Float>(transformed.x, transformed.y),
                color: color,
                uv: SIMD2<Float>(Float(i % 2), Float(i / 2)),
                shapeType: ShapeType.rect.rawValue,
                param1: 0
            ))
        }

        // 2つの三角形
        indices.append(contentsOf: [
            baseIndex, baseIndex + 1, baseIndex + 2,
            baseIndex, baseIndex + 2, baseIndex + 3
        ])
    }

    /// 楕円を追加（塗りつぶし）
    public func addEllipse(
        cx: Float, cy: Float, width: Float, height: Float,
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        ensureCapacity(vertices: 4, indices: 6)
        let baseIndex = UInt32(vertices.count)

        // バウンディングボックスの4頂点
        let halfW = width / 2
        let halfH = height / 2
        let positions = [
            SIMD2<Float>(cx - halfW, cy - halfH),
            SIMD2<Float>(cx + halfW, cy - halfH),
            SIMD2<Float>(cx + halfW, cy + halfH),
            SIMD2<Float>(cx - halfW, cy + halfH)
        ]

        let uvs = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1)
        ]

        for (i, pos) in positions.enumerated() {
            let transformed = transform * SIMD4<Float>(pos.x, pos.y, 0, 1)
            vertices.append(ShapeVertex(
                position: SIMD2<Float>(transformed.x, transformed.y),
                color: color,
                uv: uvs[i],
                shapeType: ShapeType.ellipse.rawValue,
                param1: 0
            ))
        }

        indices.append(contentsOf: [
            baseIndex, baseIndex + 1, baseIndex + 2,
            baseIndex, baseIndex + 2, baseIndex + 3
        ])
    }

    /// 線を追加
    public func addLine(
        x1: Float, y1: Float, x2: Float, y2: Float,
        color: SIMD4<Float>,
        weight: Float,
        transform: float4x4
    ) {
        ensureCapacity(vertices: 4, indices: 6)
        let baseIndex = UInt32(vertices.count)

        // 線の方向ベクトル
        let dx = x2 - x1
        let dy = y2 - y1
        let length = sqrt(dx * dx + dy * dy)

        guard length > 0 else { return }

        // 法線ベクトル（線に垂直）
        let nx = -dy / length * weight / 2
        let ny = dx / length * weight / 2

        // 4つの頂点（線を太さを持つ四角形として描画）
        let positions = [
            SIMD2<Float>(x1 + nx, y1 + ny),
            SIMD2<Float>(x2 + nx, y2 + ny),
            SIMD2<Float>(x2 - nx, y2 - ny),
            SIMD2<Float>(x1 - nx, y1 - ny)
        ]

        for pos in positions {
            let transformed = transform * SIMD4<Float>(pos.x, pos.y, 0, 1)
            vertices.append(ShapeVertex(
                position: SIMD2<Float>(transformed.x, transformed.y),
                color: color,
                uv: .zero,
                shapeType: ShapeType.line.rawValue,
                param1: weight
            ))
        }

        indices.append(contentsOf: [
            baseIndex, baseIndex + 1, baseIndex + 2,
            baseIndex, baseIndex + 2, baseIndex + 3
        ])
    }

    /// 点を追加
    public func addPoint(
        x: Float, y: Float,
        color: SIMD4<Float>,
        size: Float,
        transform: float4x4
    ) {
        ensureCapacity(vertices: 4, indices: 6)
        let baseIndex = UInt32(vertices.count)

        let halfSize = size / 2
        let positions = [
            SIMD2<Float>(x - halfSize, y - halfSize),
            SIMD2<Float>(x + halfSize, y - halfSize),
            SIMD2<Float>(x + halfSize, y + halfSize),
            SIMD2<Float>(x - halfSize, y + halfSize)
        ]

        let uvs = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1)
        ]

        for (i, pos) in positions.enumerated() {
            let transformed = transform * SIMD4<Float>(pos.x, pos.y, 0, 1)
            vertices.append(ShapeVertex(
                position: SIMD2<Float>(transformed.x, transformed.y),
                color: color,
                uv: uvs[i],
                shapeType: ShapeType.point.rawValue,
                param1: size
            ))
        }

        indices.append(contentsOf: [
            baseIndex, baseIndex + 1, baseIndex + 2,
            baseIndex, baseIndex + 2, baseIndex + 3
        ])
    }

    /// 三角形を追加
    public func addTriangle(
        x1: Float, y1: Float,
        x2: Float, y2: Float,
        x3: Float, y3: Float,
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        ensureCapacity(vertices: 3, indices: 3)
        let baseIndex = UInt32(vertices.count)

        let positions = [
            SIMD2<Float>(x1, y1),
            SIMD2<Float>(x2, y2),
            SIMD2<Float>(x3, y3)
        ]

        for pos in positions {
            let transformed = transform * SIMD4<Float>(pos.x, pos.y, 0, 1)
            vertices.append(ShapeVertex(
                position: SIMD2<Float>(transformed.x, transformed.y),
                color: color,
                uv: .zero,
                shapeType: ShapeType.triangle.rawValue,
                param1: 0
            ))
        }

        indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2])
    }

    /// 四角形の枠線を追加
    public func addRectStroke(
        x: Float, y: Float, width: Float, height: Float,
        color: SIMD4<Float>,
        weight: Float,
        transform: float4x4
    ) {
        // 4辺を線として描画
        addLine(x1: x, y1: y, x2: x + width, y2: y, color: color, weight: weight, transform: transform)
        addLine(x1: x + width, y1: y, x2: x + width, y2: y + height, color: color, weight: weight, transform: transform)
        addLine(x1: x + width, y1: y + height, x2: x, y2: y + height, color: color, weight: weight, transform: transform)
        addLine(x1: x, y1: y + height, x2: x, y2: y, color: color, weight: weight, transform: transform)
    }

    /// 楕円の枠線を追加
    public func addEllipseStroke(
        cx: Float, cy: Float, width: Float, height: Float,
        color: SIMD4<Float>,
        weight: Float,
        transform: float4x4,
        segments: Int = 32
    ) {
        let halfW = width / 2
        let halfH = height / 2

        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float(i + 1) / Float(segments) * 2 * .pi

            let x1 = cx + cos(angle1) * halfW
            let y1 = cy + sin(angle1) * halfH
            let x2 = cx + cos(angle2) * halfW
            let y2 = cy + sin(angle2) * halfH

            addLine(x1: x1, y1: y1, x2: x2, y2: y2, color: color, weight: weight, transform: transform)
        }
    }

    /// 三角形の枠線を追加
    public func addTriangleStroke(
        x1: Float, y1: Float,
        x2: Float, y2: Float,
        x3: Float, y3: Float,
        color: SIMD4<Float>,
        weight: Float,
        transform: float4x4
    ) {
        addLine(x1: x1, y1: y1, x2: x2, y2: y2, color: color, weight: weight, transform: transform)
        addLine(x1: x2, y1: y2, x2: x3, y2: y3, color: color, weight: weight, transform: transform)
        addLine(x1: x3, y1: y3, x2: x1, y2: y1, color: color, weight: weight, transform: transform)
    }

    // MARK: - Polygon Support

    /// 多角形を追加（塗りつぶし）
    /// 頂点は反時計回りで渡すことを想定
    public func addPolygon(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        guard inputVertices.count >= 3 else { return }

        // 三角形分割（ear clipping）
        let triangles = triangulate(inputVertices)

        for tri in triangles {
            addTriangle(
                x1: tri.0.x, y1: tri.0.y,
                x2: tri.1.x, y2: tri.1.y,
                x3: tri.2.x, y3: tri.2.y,
                color: color,
                transform: transform
            )
        }
    }

    /// 多角形の枠線を追加
    public func addPolygonStroke(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        weight: Float,
        transform: float4x4,
        close: Bool = true
    ) {
        guard inputVertices.count >= 2 else { return }

        for i in 0..<(inputVertices.count - 1) {
            let p1 = inputVertices[i]
            let p2 = inputVertices[i + 1]
            addLine(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, color: color, weight: weight, transform: transform)
        }

        // 閉じる場合は最後から最初への線も追加
        if close && inputVertices.count >= 3 {
            let last = inputVertices[inputVertices.count - 1]
            let first = inputVertices[0]
            addLine(x1: last.x, y1: last.y, x2: first.x, y2: first.y, color: color, weight: weight, transform: transform)
        }
    }

    /// 連続した三角形ストリップを追加
    public func addTriangleStrip(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        guard inputVertices.count >= 3 else { return }

        for i in 0..<(inputVertices.count - 2) {
            let v0 = inputVertices[i]
            let v1 = inputVertices[i + 1]
            let v2 = inputVertices[i + 2]

            // 偶数インデックスは順方向、奇数は逆方向で巻き順を維持
            if i % 2 == 0 {
                addTriangle(x1: v0.x, y1: v0.y, x2: v1.x, y2: v1.y, x3: v2.x, y3: v2.y, color: color, transform: transform)
            } else {
                addTriangle(x1: v0.x, y1: v0.y, x2: v2.x, y2: v2.y, x3: v1.x, y3: v1.y, color: color, transform: transform)
            }
        }
    }

    /// 三角形ファンを追加（最初の頂点を中心とする）
    public func addTriangleFan(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        guard inputVertices.count >= 3 else { return }

        let center = inputVertices[0]
        for i in 1..<(inputVertices.count - 1) {
            let v1 = inputVertices[i]
            let v2 = inputVertices[i + 1]
            addTriangle(x1: center.x, y1: center.y, x2: v1.x, y2: v1.y, x3: v2.x, y3: v2.y, color: color, transform: transform)
        }
    }

    /// 連続した四角形を追加（QUAD_STRIPモード）
    public func addQuadStrip(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        guard inputVertices.count >= 4 && inputVertices.count % 2 == 0 else { return }

        for i in stride(from: 0, to: inputVertices.count - 2, by: 2) {
            let v0 = inputVertices[i]
            let v1 = inputVertices[i + 1]
            let v2 = inputVertices[i + 3]
            let v3 = inputVertices[i + 2]

            addTriangle(x1: v0.x, y1: v0.y, x2: v1.x, y2: v1.y, x3: v2.x, y3: v2.y, color: color, transform: transform)
            addTriangle(x1: v0.x, y1: v0.y, x2: v2.x, y2: v2.y, x3: v3.x, y3: v3.y, color: color, transform: transform)
        }
    }

    /// 独立した四角形を追加（QUADSモード）
    public func addQuads(
        vertices inputVertices: [SIMD2<Float>],
        color: SIMD4<Float>,
        transform: float4x4
    ) {
        guard inputVertices.count >= 4 && inputVertices.count % 4 == 0 else { return }

        for i in stride(from: 0, to: inputVertices.count, by: 4) {
            let v0 = inputVertices[i]
            let v1 = inputVertices[i + 1]
            let v2 = inputVertices[i + 2]
            let v3 = inputVertices[i + 3]

            addTriangle(x1: v0.x, y1: v0.y, x2: v1.x, y2: v1.y, x3: v2.x, y3: v2.y, color: color, transform: transform)
            addTriangle(x1: v0.x, y1: v0.y, x2: v2.x, y2: v2.y, x3: v3.x, y3: v3.y, color: color, transform: transform)
        }
    }

    // MARK: - Triangulation (Ear Clipping)

    /// 簡易的なear clippingアルゴリズムで多角形を三角形分割
    private func triangulate(_ inputVertices: [SIMD2<Float>]) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
        guard inputVertices.count >= 3 else { return [] }

        // 凸多角形の簡易判定と処理
        if isConvex(inputVertices) {
            return triangulateConvex(inputVertices)
        }

        // 凹多角形のear clipping
        var remaining = Array(inputVertices)
        var triangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []

        // 時計回りかチェックして、反時計回りに変換
        if signedArea(remaining) > 0 {
            remaining.reverse()
        }

        var safety = remaining.count * remaining.count
        while remaining.count > 3 && safety > 0 {
            safety -= 1
            var earFound = false

            for i in 0..<remaining.count {
                let prev = remaining[(i + remaining.count - 1) % remaining.count]
                let curr = remaining[i]
                let next = remaining[(i + 1) % remaining.count]

                if isEar(prev: prev, curr: curr, next: next, polygon: remaining) {
                    triangles.append((prev, curr, next))
                    remaining.remove(at: i)
                    earFound = true
                    break
                }
            }

            if !earFound {
                // earが見つからない場合は強制的に最初の3頂点を使う
                break
            }
        }

        // 残りの3頂点で最後の三角形
        if remaining.count == 3 {
            triangles.append((remaining[0], remaining[1], remaining[2]))
        }

        return triangles
    }

    private func triangulateConvex(_ vertices: [SIMD2<Float>]) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
        var triangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        let center = vertices[0]
        for i in 1..<(vertices.count - 1) {
            triangles.append((center, vertices[i], vertices[i + 1]))
        }
        return triangles
    }

    private func isConvex(_ vertices: [SIMD2<Float>]) -> Bool {
        guard vertices.count >= 3 else { return false }

        var sign: Float = 0
        for i in 0..<vertices.count {
            let p0 = vertices[i]
            let p1 = vertices[(i + 1) % vertices.count]
            let p2 = vertices[(i + 2) % vertices.count]

            let cross = (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x)

            if sign == 0 {
                sign = cross
            } else if sign * cross < 0 {
                return false
            }
        }
        return true
    }

    private func signedArea(_ vertices: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        for i in 0..<vertices.count {
            let p1 = vertices[i]
            let p2 = vertices[(i + 1) % vertices.count]
            area += (p2.x - p1.x) * (p2.y + p1.y)
        }
        return area / 2
    }

    private func isEar(prev: SIMD2<Float>, curr: SIMD2<Float>, next: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        // 凸頂点かチェック（反時計回りで左回りが凸）
        let cross = (curr.x - prev.x) * (next.y - prev.y) - (curr.y - prev.y) * (next.x - prev.x)
        if cross >= 0 { return false }

        // 三角形内に他の頂点がないかチェック
        for p in polygon {
            if p == prev || p == curr || p == next { continue }
            if pointInTriangle(p, prev, curr, next) { return false }
        }

        return true
    }

    private func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let v0 = c - a
        let v1 = b - a
        let v2 = p - a

        let dot00 = v0.x * v0.x + v0.y * v0.y
        let dot01 = v0.x * v1.x + v0.y * v1.y
        let dot02 = v0.x * v2.x + v0.y * v2.y
        let dot11 = v1.x * v1.x + v1.y * v1.y
        let dot12 = v1.x * v2.x + v1.y * v2.y

        let invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom

        return (u >= 0) && (v >= 0) && (u + v < 1)
    }

    // MARK: - Rendering

    /// バッチされた描画コマンドを実行
    public func flush(to encoder: MTLRenderCommandEncoder) {
        guard !vertices.isEmpty else { return }

        // 頂点データをバッファにコピー
        vertexBuffer?.contents().copyMemory(
            from: vertices,
            byteCount: MemoryLayout<ShapeVertex>.stride * vertices.count
        )

        // インデックスデータをバッファにコピー
        indexBuffer?.contents().copyMemory(
            from: indices,
            byteCount: MemoryLayout<UInt32>.stride * indices.count
        )

        // 正射影行列を設定（Processing座標系: 左上原点、Y下向き）
        let projection = float4x4(
            orthographic: 0, right: canvasWidth,
            bottom: canvasHeight, top: 0,
            near: -1, far: 1
        )
        var uniforms = ShapeUniforms(projection: projection)
        uniformBuffer?.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<ShapeUniforms>.stride
        )

        // 描画
        encoder.setRenderPipelineState(pipelines.shapeFillPipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint32,
            indexBuffer: indexBuffer!,
            indexBufferOffset: 0
        )

        // バッファをクリア
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
    }

    /// バッファをクリア（描画せずにリセット）
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
    }
}
