import Metal
import simd

// MARK: - MShape Drawing Integration

/// Extension on SketchContext that provides the core rendering logic for retained-mode shapes.
/// Routes shape drawing through existing Canvas2D/Canvas3D pipelines.
extension SketchContext {

    // MARK: - Public Entry Points

    /// Draw a retained shape at the origin.
    public func shape(_ s: MShape) {
        if s.is3D {
            drawShape3D(s, tx: 0, ty: 0, tz: 0)
        } else {
            drawShape2D(s, tx: 0, ty: 0)
        }
    }

    /// Draw a retained shape at the given position.
    public func shape(_ s: MShape, _ x: Float, _ y: Float) {
        if s.is3D {
            drawShape3D(s, tx: x, ty: y, tz: 0)
        } else {
            drawShape2D(s, tx: x, ty: y)
        }
    }

    /// Draw a retained shape at the given position and size.
    ///
    /// For primitive shapes, the size overrides the shape's original dimensions.
    /// For custom shapes, the shape is scaled to fit the given bounds.
    public func shape(_ s: MShape, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        if s.is3D {
            drawShape3DWithSize(s, tx: x, ty: y, tz: 0, w: w, h: h)
        } else {
            drawShape2DWithSize(s, tx: x, ty: y, w: w, h: h)
        }
    }

    // MARK: - 2D Drawing

    func drawShape2D(_ s: MShape, tx: Float, ty: Float) {
        // Push transform
        canvas.pushMatrix()
        if tx != 0 || ty != 0 {
            canvas.translate(tx, ty)
        }
        if s.localTransform2D != float3x3(1) {
            canvas.applyMatrix(s.localTransform2D)
        }

        // Push style if shape has its own
        let applyStyle = s.styleEnabled
        if applyStyle {
            canvas.pushStyle()
            applyShapeStyle2D(s)
        }

        // Draw based on kind
        switch s.kind {
        case .rect(let x, let y, let w, let h):
            canvas.rect(x, y, w, h)

        case .ellipse(let x, let y, let w, let h):
            canvas.ellipse(x, y, w, h)

        case .triangle(let x1, let y1, let x2, let y2, let x3, let y3):
            canvas.triangle(x1, y1, x2, y2, x3, y3)

        case .quad(let x1, let y1, let x2, let y2, let x3, let y3, let x4, let y4):
            canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4)

        case .arc(let x, let y, let w, let h, let start, let stop, let mode):
            canvas.arc(x, y, w, h, start, stop, mode)

        case .line(let x1, let y1, let x2, let y2):
            canvas.line(x1, y1, x2, y2)

        case .point(let x, let y):
            canvas.point(x, y)

        case .path2D:
            drawPath2D(s)

        case .group:
            for child in s.children {
                if child.is3D {
                    drawShape3D(child, tx: 0, ty: 0, tz: 0)
                } else {
                    drawShape2D(child, tx: 0, ty: 0)
                }
            }

        default:
            // 3D kinds drawn through 2D context — fall through to 3D path
            drawShape3D(s, tx: 0, ty: 0, tz: 0)
        }

        // Restore
        if applyStyle {
            canvas.popStyle()
        }
        canvas.popMatrix()
    }

    private func drawShape2DWithSize(_ s: MShape, tx: Float, ty: Float, w: Float, h: Float) {
        canvas.pushMatrix()
        canvas.translate(tx, ty)

        if s.localTransform2D != float3x3(1) {
            canvas.applyMatrix(s.localTransform2D)
        }

        let applyStyle = s.styleEnabled
        if applyStyle {
            canvas.pushStyle()
            applyShapeStyle2D(s)
        }

        switch s.kind {
        case .rect:
            canvas.rect(0, 0, w, h)

        case .ellipse:
            canvas.ellipse(0, 0, w, h)

        case .path2D:
            // Scale to fit bounding box
            let bounds = computeBounds2D(s)
            if bounds.width > 0 && bounds.height > 0 {
                canvas.scale(w / bounds.width, h / bounds.height)
                canvas.translate(-bounds.minX, -bounds.minY)
            }
            drawPath2D(s)

        case .group:
            // Apply uniform scale for groups
            canvas.scale(w, h)
            for child in s.children {
                if child.is3D {
                    drawShape3D(child, tx: 0, ty: 0, tz: 0)
                } else {
                    drawShape2D(child, tx: 0, ty: 0)
                }
            }

        default:
            break
        }

        if applyStyle { canvas.popStyle() }
        canvas.popMatrix()
    }

    private func drawPath2D(_ s: MShape) {
        s.ensureCacheValid()

        // Draw fill triangles
        if canvas.hasFill, let tris = s.cachedTriangles2D, !tris.isEmpty {
            let fillColor = canvas.fillColor
            for (v0, v1, v2) in tris {
                // Check for per-vertex colors
                canvas.addTriangle(v0.x, v0.y, v1.x, v1.y, v2.x, v2.y, fillColor)
            }
        }

        // Draw stroke
        if canvas.hasStroke, let outline = s.cachedStrokeOutline2D, outline.count >= 2 {
            canvas.strokePolyline(outline, closed: s.closeMode2D == .close)
        }
    }

    private func applyShapeStyle2D(_ s: MShape) {
        let style = s.capturedStyle
        canvas.fillColor = style.fillColor
        canvas.hasFill = style.hasFill
        canvas.strokeColor = style.strokeColor
        canvas.hasStroke = style.hasStroke
        canvas.currentStrokeWeight = style.strokeWeight
    }

    private func computeBounds2D(_ s: MShape) -> (minX: Float, minY: Float, width: Float, height: Float) {
        guard !s.vertices2D.isEmpty else { return (0, 0, 0, 0) }
        var minX: Float = .greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        for v in s.vertices2D {
            minX = min(minX, v.position.x)
            minY = min(minY, v.position.y)
            maxX = max(maxX, v.position.x)
            maxY = max(maxY, v.position.y)
        }
        return (minX, minY, maxX - minX, maxY - minY)
    }

    // MARK: - 3D Drawing

    func drawShape3D(_ s: MShape, tx: Float, ty: Float, tz: Float) {
        canvas3D.pushState()
        if tx != 0 || ty != 0 || tz != 0 {
            canvas3D.translate(tx, ty, tz)
        }
        if s.localTransform3D != .identity {
            canvas3D.applyMatrix(s.localTransform3D)
        }

        let applyStyle = s.styleEnabled
        if applyStyle {
            applyShapeStyle3D(s)
        }

        switch s.kind {
        case .box(let w, let h, let d):
            ensurePrimitiveMesh3D(s, .box(width: w, height: h, depth: d))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .sphere(let r, let detail):
            ensurePrimitiveMesh3D(s, .sphere(radius: r, detail: detail))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .plane(let w, let h):
            ensurePrimitiveMesh3D(s, .plane(width: w, height: h))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .cylinder(let r, let h, let detail):
            ensurePrimitiveMesh3D(s, .cylinder(radius: r, height: h, detail: detail))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .cone(let r, let h, let detail):
            ensurePrimitiveMesh3D(s, .cone(radius: r, height: h, detail: detail))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .torus(let rr, let tr, let detail):
            ensurePrimitiveMesh3D(s, .torus(ringRadius: rr, tubeRadius: tr, detail: detail))
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .path3D:
            s.ensureCacheValid()
            if let mesh = s.cachedMesh3D { canvas3D.mesh(mesh) }

        case .group:
            for child in s.children {
                if child.is3D {
                    drawShape3D(child, tx: 0, ty: 0, tz: 0)
                } else {
                    drawShape2D(child, tx: 0, ty: 0)
                }
            }

        default:
            // 2D kinds drawn through 3D context — delegate to 2D
            drawShape2D(s, tx: 0, ty: 0)
        }

        canvas3D.popState()
    }

    private func drawShape3DWithSize(_ s: MShape, tx: Float, ty: Float, tz: Float,
                                      w: Float, h: Float) {
        canvas3D.pushState()
        canvas3D.translate(tx, ty, tz)

        if s.localTransform3D != .identity {
            canvas3D.applyMatrix(s.localTransform3D)
        }

        let applyStyle = s.styleEnabled
        if applyStyle {
            applyShapeStyle3D(s)
        }

        // Override the primitive with the given size
        switch s.kind {
        case .box:
            ensurePrimitiveMesh3DForSize(s, width: w, height: h, depth: w)
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .sphere:
            ensurePrimitiveMesh3DForSize(s, width: w, height: h, depth: w)
            if let mesh = s.primitiveMesh3D { canvas3D.mesh(mesh) }

        case .path3D:
            canvas3D.scale(w, h, w)
            s.ensureCacheValid()
            if let mesh = s.cachedMesh3D { canvas3D.mesh(mesh) }

        case .group:
            canvas3D.scale(w, h, w)
            for child in s.children {
                if child.is3D {
                    drawShape3D(child, tx: 0, ty: 0, tz: 0)
                } else {
                    drawShape2D(child, tx: 0, ty: 0)
                }
            }

        default:
            break
        }

        canvas3D.popState()
    }

    private func applyShapeStyle3D(_ s: MShape) {
        let style = s.capturedStyle
        canvas3D.fillColor = style.fillColor
        canvas3D.hasFill = style.hasFill
        canvas3D.hasStroke = style.hasStroke
        canvas3D.strokeColor = style.strokeColor
        if let material = style.material {
            canvas3D.currentMaterial = material
        }
        if let tex = s.texture {
            canvas3D.currentTexture = tex
        }
    }

    private func ensurePrimitiveMesh3D(_ s: MShape, _ kind: ShapeKind) {
        if s.primitiveMesh3D != nil { return }
        let device = renderer.device
        do {
            switch kind {
            case .box(let w, let h, let d):
                s.primitiveMesh3D = try Mesh.box(device: device, width: w, height: h, depth: d)
            case .sphere(let r, let detail):
                let rings = max(detail / 2, 4)
                s.primitiveMesh3D = try Mesh.sphere(device: device, radius: r, segments: detail, rings: rings)
            case .plane(let w, let h):
                s.primitiveMesh3D = try Mesh.plane(device: device, width: w, height: h)
            case .cylinder(let r, let h, let detail):
                s.primitiveMesh3D = try Mesh.cylinder(device: device, radius: r, height: h, segments: detail)
            case .cone(let r, let h, let detail):
                s.primitiveMesh3D = try Mesh.cone(device: device, radius: r, height: h, segments: detail)
            case .torus(let rr, let tr, let detail):
                s.primitiveMesh3D = try Mesh.torus(device: device, ringRadius: rr, tubeRadius: tr, segments: detail)
            default:
                break
            }
        } catch {
            metaphorWarning("Failed to create primitive mesh for MShape: \(error)")
        }
    }

    private func ensurePrimitiveMesh3DForSize(_ s: MShape, width: Float, height: Float, depth: Float) {
        let device = renderer.device
        do {
            switch s.kind {
            case .box:
                s.primitiveMesh3D = try Mesh.box(device: device, width: width, height: height, depth: depth)
            case .sphere(_, let detail):
                let r = min(width, height) / 2
                let rings = max(detail / 2, 4)
                s.primitiveMesh3D = try Mesh.sphere(device: device, radius: r, segments: detail, rings: rings)
            default:
                break
            }
        } catch {
            metaphorWarning("Failed to create sized primitive mesh for MShape: \(error)")
        }
    }
}
