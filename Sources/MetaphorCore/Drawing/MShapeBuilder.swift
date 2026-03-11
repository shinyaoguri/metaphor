import Metal
import simd

// MARK: - Shape Building API (beginShape / vertex / endShape)

extension MShape {

    // MARK: - beginShape

    /// Begin recording vertices for a custom shape.
    ///
    /// Call `vertex()` to add points, then `endShape()` to finalize.
    /// Optionally call `beginContour()`/`endContour()` for holes (2D only).
    ///
    /// - Parameter mode: The primitive drawing mode (default: `.polygon`).
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

    // MARK: - 2D Vertex

    /// Add a 2D vertex to the shape being recorded.
    public func vertex(_ x: Float, _ y: Float) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y)))
    }

    /// Add a 2D vertex with per-vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y), color: color.simd))
    }

    /// Add a 2D vertex with texture coordinates.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        guard isRecording else { return }
        if !kind.isPath {
            kind = .path2D
        }
        vertices2D.append(ShapeVertex2D(position: SIMD2(x, y), uv: SIMD2(u, v)))
    }

    // MARK: - 3D Vertex

    /// Add a 3D vertex to the shape being recorded.
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(position: SIMD3(x, y, z), normal: normal))
        pendingNormal3D = nil
    }

    /// Add a 3D vertex with texture coordinates.
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ u: Float, _ v: Float) {
        guard isRecording else { return }
        kind = .path3D
        let normal = pendingNormal3D ?? SIMD3(0, 1, 0)
        vertices3D.append(ShapeVertex3D(
            position: SIMD3(x, y, z), normal: normal, uv: SIMD2(u, v)))
        pendingNormal3D = nil
    }

    /// Set the normal vector for the next 3D vertex.
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal3D = SIMD3(nx, ny, nz)
    }

    // MARK: - Contours (2D holes)

    /// Begin a contour (hole) within a 2D shape.
    ///
    /// Vertices added after this call and before `endContour()` define the hole boundary.
    public func beginContour() {
        guard isRecording else { return }
        isInContour = true
        contourStartIndex = vertices2D.count
    }

    /// End a contour (hole) within a 2D shape.
    public func endContour() {
        guard isRecording, isInContour else { return }
        isInContour = false
        let endIndex = vertices2D.count
        if endIndex > contourStartIndex {
            contourRanges.append(contourStartIndex..<endIndex)
        }
    }

    // MARK: - Style During Definition

    /// Set the fill color during shape definition.
    public func fill(_ color: Color) {
        capturedStyle.fillColor = color.simd
        capturedStyle.hasFill = true
    }

    /// Set the fill color from a grayscale value (0-255).
    public func fill(_ gray: Float) {
        let v = gray / 255.0
        capturedStyle.fillColor = SIMD4(v, v, v, 1)
        capturedStyle.hasFill = true
    }

    /// Disable fill.
    public func noFill() {
        capturedStyle.hasFill = false
    }

    /// Set the stroke color during shape definition.
    public func stroke(_ color: Color) {
        capturedStyle.strokeColor = color.simd
        capturedStyle.hasStroke = true
    }

    /// Set the stroke color from a grayscale value (0-255).
    public func stroke(_ gray: Float) {
        let v = gray / 255.0
        capturedStyle.strokeColor = SIMD4(v, v, v, 1)
        capturedStyle.hasStroke = true
    }

    /// Disable stroke.
    public func noStroke() {
        capturedStyle.hasStroke = false
    }

    /// Set the stroke weight during shape definition.
    public func strokeWeight(_ weight: Float) {
        capturedStyle.strokeWeight = weight
    }

    // MARK: - endShape

    /// Finalize the shape and build geometry from recorded vertices.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape(_ close: CloseMode = .open) {
        guard isRecording else { return }
        isRecording = false

        if case .path2D = kind {
            closeMode2D = close
        } else if case .path3D = kind {
            closeMode3D = close
        }

        // Geometry will be built lazily on first draw
        isDirty = true
    }
}

// MARK: - Tessellation / Mesh Building

extension MShape {

    /// Tessellate the 2D custom shape and cache the result.
    ///
    /// Uses `EarClipTriangulator` for polygon mode.
    /// Call only when `isDirty` is true or cache is nil.
    func tessellate2D() {
        guard case .path2D = kind, !vertices2D.isEmpty else {
            cachedTriangles2D = []
            cachedStrokeOutline2D = []
            isDirty = false
            return
        }

        // Extract outer polygon (vertices not in any contour range)
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
            // No fill tessellation for lines/points modes
            cachedTriangles2D = []
        }

        // Build stroke outline
        cachedStrokeOutline2D = outerPoints
        isDirty = false
    }

    private func tessellatePolygon2D(outerPoints: [(Float, Float)]) {
        guard outerPoints.count >= 3 else {
            cachedTriangles2D = []
            return
        }

        if contourRanges.isEmpty {
            // Simple polygon without holes
            let indices = EarClipTriangulator.triangulate(outerPoints)
            cachedTriangles2D = buildTrianglesFromIndices(indices, points: outerPoints)
        } else {
            // Polygon with holes
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

    /// Build a Mesh from the 3D custom shape vertices and cache the result.
    func buildMesh3D() {
        guard case .path3D = kind, !vertices3D.isEmpty else {
            cachedMesh3D = nil
            isDirty = false
            return
        }

        let hasUVs = vertices3D.contains { $0.uv != nil }
        let white = SIMD4<Float>(1, 1, 1, 1)

        // Build Vertex3D array
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

        // Build index array based on shape mode
        var indices: [UInt16] = []
        switch shapeMode3D {
        case .polygon:
            // Fan tessellation for polygon mode
            if vertices3D.count >= 3 {
                for i in 1..<(vertices3D.count - 1) {
                    indices.append(contentsOf: [0, UInt16(i), UInt16(i + 1)])
                }
                if closeMode3D == .close && vertices3D.count >= 3 {
                    // Already closed by fan
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
            // Handled differently during drawing, no fill mesh
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

    /// Ensure the geometry cache is up to date. Called before drawing.
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
