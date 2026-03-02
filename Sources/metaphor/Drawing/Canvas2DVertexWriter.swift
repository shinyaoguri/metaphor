import Metal
import simd

// MARK: - Vertex Writing

extension Canvas2D {

    /// Adds a vertex with the current transform applied.
    func addVertex(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        hasDrawnAnything = true
        // Flush textured vertices when switching back to color mode (preserves draw order)
        if texturedVertexCount > 0 {
            flushTexturedVertices()
            currentBoundTexture = nil
        }
        // Flush any pending instanced batch first (preserves draw order)
        if instanceBatcher2D.instanceCount > 0 {
            flushInstancedBatch()
        }
        if bufferOffset + vertexCount >= maxVertices {
            flushColorVertices()
            bufferOffset = 0
        }
        let writeIndex = bufferOffset + vertexCount
        precondition(writeIndex < maxVertices,
                     "[metaphor] Vertex buffer overflow: \(writeIndex) >= \(maxVertices)")
        let p = currentTransform * SIMD3<Float>(x, y, 1)
        vertices[writeIndex] = Vertex2D(
            posX: p.x, posY: p.y,
            r: color.x, g: color.y, b: color.z, a: color.w
        )
        vertexCount += 1
    }

    /// Adds a vertex without transform (used for background fills).
    func addVertexRaw(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        if texturedVertexCount > 0 {
            flushTexturedVertices()
            currentBoundTexture = nil
        }
        if instanceBatcher2D.instanceCount > 0 {
            flushInstancedBatch()
        }
        if bufferOffset + vertexCount >= maxVertices {
            flushColorVertices()
            bufferOffset = 0
        }
        let writeIndex = bufferOffset + vertexCount
        precondition(writeIndex < maxVertices,
                     "[metaphor] Vertex buffer overflow: \(writeIndex) >= \(maxVertices)")
        vertices[writeIndex] = Vertex2D(
            posX: x, posY: y,
            r: color.x, g: color.y, b: color.z, a: color.w
        )
        vertexCount += 1
    }

    /// Adds a triangle with the current transform applied.
    func addTriangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ color: SIMD4<Float>
    ) {
        addVertex(x1, y1, color)
        addVertex(x2, y2, color)
        addVertex(x3, y3, color)
    }

    /// Draws a stroke line as a quad with optional start/end caps.
    func strokeLine(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float,
                    capStart: Bool = true, capEnd: Bool = true) {
        let dx = x2 - x1
        let dy = y2 - y1
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }

        let hw = currentStrokeWeight * 0.5
        let nx = -dy / len * hw
        let ny = dx / len * hw
        let tx = dx / len * hw
        let ty = dy / len * hw

        var sx1 = x1, sy1 = y1, sx2 = x2, sy2 = y2
        if currentStrokeCap == .square {
            if capStart { sx1 -= tx; sy1 -= ty }
            if capEnd   { sx2 += tx; sy2 += ty }
        }

        addVertex(sx1 + nx, sy1 + ny, strokeColor)
        addVertex(sx1 - nx, sy1 - ny, strokeColor)
        addVertex(sx2 + nx, sy2 + ny, strokeColor)
        addVertex(sx1 - nx, sy1 - ny, strokeColor)
        addVertex(sx2 - nx, sy2 - ny, strokeColor)
        addVertex(sx2 + nx, sy2 + ny, strokeColor)

        if currentStrokeCap == .round {
            let capSegments = 8
            if capStart {
                let baseAngle = atan2(-dy, -dx)
                for i in 0..<capSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(capSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(capSegments)
                    addVertex(x1, y1, strokeColor)
                    addVertex(x1 + hw * cos(a0), y1 + hw * sin(a0), strokeColor)
                    addVertex(x1 + hw * cos(a1), y1 + hw * sin(a1), strokeColor)
                }
            }
            if capEnd {
                let baseAngle = atan2(dy, dx)
                for i in 0..<capSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(capSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(capSegments)
                    addVertex(x2, y2, strokeColor)
                    addVertex(x2 + hw * cos(a0), y2 + hw * sin(a0), strokeColor)
                    addVertex(x2 + hw * cos(a1), y2 + hw * sin(a1), strokeColor)
                }
            }
        }
    }

    /// Draws a polyline stroke with join support (bevel, miter, round).
    func strokePolyline(_ points: [(Float, Float)], closed: Bool) {
        let count = points.count
        guard count >= 2 else { return }

        let hw = currentStrokeWeight * 0.5
        let joinSegments = 8

        struct SegInfo {
            var dx: Float; var dy: Float; var len: Float
            var nx: Float; var ny: Float
        }

        let segCount = closed ? count : count - 1
        var segs: [SegInfo] = []
        segs.reserveCapacity(segCount)

        for i in 0..<segCount {
            let j = (i + 1) % count
            let dx = points[j].0 - points[i].0
            let dy = points[j].1 - points[i].1
            let len = sqrt(dx * dx + dy * dy)
            if len > 0 {
                segs.append(SegInfo(dx: dx, dy: dy, len: len,
                                    nx: -dy / len * hw, ny: dx / len * hw))
            } else {
                segs.append(SegInfo(dx: 0, dy: 0, len: 0, nx: 0, ny: 0))
            }
        }

        for i in 0..<segCount {
            let s = segs[i]
            guard s.len > 0 else { continue }
            let p0 = points[i]
            let p1 = points[(i + 1) % count]
            addVertex(p0.0 + s.nx, p0.1 + s.ny, strokeColor)
            addVertex(p0.0 - s.nx, p0.1 - s.ny, strokeColor)
            addVertex(p1.0 + s.nx, p1.1 + s.ny, strokeColor)
            addVertex(p0.0 - s.nx, p0.1 - s.ny, strokeColor)
            addVertex(p1.0 - s.nx, p1.1 - s.ny, strokeColor)
            addVertex(p1.0 + s.nx, p1.1 + s.ny, strokeColor)
        }

        let joinCount = closed ? count : count - 2
        let joinStart = closed ? 0 : 1
        for k in 0..<joinCount {
            let idx = (joinStart + k) % count
            let prevSeg = closed ? (idx - 1 + segCount) % segCount : idx - 1
            let nextSeg = closed ? idx : idx

            let s0 = segs[prevSeg]
            let s1 = segs[nextSeg]
            guard s0.len > 0 && s1.len > 0 else { continue }

            let px = points[idx].0
            let py = points[idx].1

            let cross = s0.dx * s1.dy - s0.dy * s1.dx

            switch currentStrokeJoin {
            case .bevel:
                if cross > 0 {
                    addVertex(px, py, strokeColor)
                    addVertex(px - s0.nx, py - s0.ny, strokeColor)
                    addVertex(px - s1.nx, py - s1.ny, strokeColor)
                } else {
                    addVertex(px, py, strokeColor)
                    addVertex(px + s0.nx, py + s0.ny, strokeColor)
                    addVertex(px + s1.nx, py + s1.ny, strokeColor)
                }

            case .miter:
                let dot = s0.nx * s1.nx + s0.ny * s1.ny
                let miterLen = hw / max(sqrt((1.0 + dot / (hw * hw)) * 0.5), 0.001)
                if miterLen > hw * 4.0 {
                    if cross > 0 {
                        addVertex(px, py, strokeColor)
                        addVertex(px - s0.nx, py - s0.ny, strokeColor)
                        addVertex(px - s1.nx, py - s1.ny, strokeColor)
                    } else {
                        addVertex(px, py, strokeColor)
                        addVertex(px + s0.nx, py + s0.ny, strokeColor)
                        addVertex(px + s1.nx, py + s1.ny, strokeColor)
                    }
                } else {
                    if cross > 0 {
                        let mx = -(s0.nx + s1.nx)
                        let my = -(s0.ny + s1.ny)
                        let mlen = sqrt(mx * mx + my * my)
                        if mlen > 0 {
                            let scale = miterLen / mlen
                            addVertex(px, py, strokeColor)
                            addVertex(px - s0.nx, py - s0.ny, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px, py, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px - s1.nx, py - s1.ny, strokeColor)
                        }
                    } else {
                        let mx = s0.nx + s1.nx
                        let my = s0.ny + s1.ny
                        let mlen = sqrt(mx * mx + my * my)
                        if mlen > 0 {
                            let scale = miterLen / mlen
                            addVertex(px, py, strokeColor)
                            addVertex(px + s0.nx, py + s0.ny, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px, py, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px + s1.nx, py + s1.ny, strokeColor)
                        }
                    }
                }

            case .round:
                let angle0: Float
                let angle1: Float
                if cross > 0 {
                    angle0 = atan2(-s0.ny, -s0.nx)
                    angle1 = atan2(-s1.ny, -s1.nx)
                } else {
                    angle0 = atan2(s0.ny, s0.nx)
                    angle1 = atan2(s1.ny, s1.nx)
                }
                var sweep = angle1 - angle0
                if cross > 0 {
                    if sweep > 0 { sweep -= Float.pi * 2 }
                } else {
                    if sweep < 0 { sweep += Float.pi * 2 }
                }

                for i in 0..<joinSegments {
                    let a0 = angle0 + sweep * Float(i) / Float(joinSegments)
                    let a1 = angle0 + sweep * Float(i + 1) / Float(joinSegments)
                    addVertex(px, py, strokeColor)
                    addVertex(px + hw * cos(a0), py + hw * sin(a0), strokeColor)
                    addVertex(px + hw * cos(a1), py + hw * sin(a1), strokeColor)
                }
            }
        }

        if !closed {
            let s0 = segs[0]
            let sLast = segs[segCount - 1]

            if currentStrokeCap == .round && s0.len > 0 {
                let baseAngle = atan2(-s0.dy, -s0.dx)
                let p = points[0]
                for i in 0..<joinSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(joinSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(joinSegments)
                    addVertex(p.0, p.1, strokeColor)
                    addVertex(p.0 + hw * cos(a0), p.1 + hw * sin(a0), strokeColor)
                    addVertex(p.0 + hw * cos(a1), p.1 + hw * sin(a1), strokeColor)
                }
            } else if currentStrokeCap == .square && s0.len > 0 {
                let tx = s0.dx / s0.len * hw
                let ty = s0.dy / s0.len * hw
                let p = points[0]
                addVertex(p.0 + s0.nx - tx, p.1 + s0.ny - ty, strokeColor)
                addVertex(p.0 - s0.nx - tx, p.1 - s0.ny - ty, strokeColor)
                addVertex(p.0 + s0.nx, p.1 + s0.ny, strokeColor)
                addVertex(p.0 - s0.nx - tx, p.1 - s0.ny - ty, strokeColor)
                addVertex(p.0 - s0.nx, p.1 - s0.ny, strokeColor)
                addVertex(p.0 + s0.nx, p.1 + s0.ny, strokeColor)
            }

            if currentStrokeCap == .round && sLast.len > 0 {
                let baseAngle = atan2(sLast.dy, sLast.dx)
                let p = points[count - 1]
                for i in 0..<joinSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(joinSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(joinSegments)
                    addVertex(p.0, p.1, strokeColor)
                    addVertex(p.0 + hw * cos(a0), p.1 + hw * sin(a0), strokeColor)
                    addVertex(p.0 + hw * cos(a1), p.1 + hw * sin(a1), strokeColor)
                }
            } else if currentStrokeCap == .square && sLast.len > 0 {
                let tx = sLast.dx / sLast.len * hw
                let ty = sLast.dy / sLast.len * hw
                let p = points[count - 1]
                addVertex(p.0 + sLast.nx, p.1 + sLast.ny, strokeColor)
                addVertex(p.0 - sLast.nx, p.1 - sLast.ny, strokeColor)
                addVertex(p.0 + sLast.nx + tx, p.1 + sLast.ny + ty, strokeColor)
                addVertex(p.0 - sLast.nx, p.1 - sLast.ny, strokeColor)
                addVertex(p.0 - sLast.nx + tx, p.1 - sLast.ny + ty, strokeColor)
                addVertex(p.0 + sLast.nx + tx, p.1 + sLast.ny + ty, strokeColor)
            }
        }
    }
}
