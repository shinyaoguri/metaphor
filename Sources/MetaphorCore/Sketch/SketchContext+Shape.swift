import Metal
import simd

// MARK: - Shape Factory Methods

extension SketchContext {

    /// Create a retained shape from a ``ShapeKind``.
    ///
    /// The shape captures the current fill, stroke, and material state.
    /// For custom shapes, use ``createShape()`` followed by `beginShape`/`vertex`/`endShape`.
    ///
    /// ```swift
    /// let box = createShape(.box(width: 1, height: 1, depth: 1))
    /// let circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 100))
    /// let group = createShape(.group)
    /// ```
    ///
    /// - Parameter kind: The type of shape to create.
    /// - Returns: A new ``MShape`` instance.
    public func createShape(_ kind: ShapeKind) -> MShape {
        let style = captureCurrentStyle()
        return MShape(device: renderer.device, kind: kind, style: style)
    }

    /// Create an empty retained shape for custom geometry definition.
    ///
    /// Use `beginShape()`, `vertex()`, and `endShape()` on the returned shape
    /// to define its geometry.
    ///
    /// ```swift
    /// let star = createShape()
    /// star.beginShape()
    /// star.fill(.yellow)
    /// for i in 0..<10 {
    ///     let angle = Float(i) * Float.pi / 5
    ///     let r: Float = (i % 2 == 0) ? 100 : 40
    ///     star.vertex(cos(angle) * r, sin(angle) * r)
    /// }
    /// star.endShape(.close)
    /// ```
    ///
    /// - Returns: A new ``MShape`` instance with kind `.path2D`.
    public func createShape() -> MShape {
        let style = captureCurrentStyle()
        return MShape(device: renderer.device, kind: .path2D, style: style)
    }

    // MARK: - Style Capture

    /// Snapshot the current drawing style from Canvas2D and Canvas3D.
    private func captureCurrentStyle() -> ShapeStyle {
        var style = ShapeStyle()
        style.fillColor = canvas.fillColor
        style.strokeColor = canvas.strokeColor
        style.strokeWeight = canvas.currentStrokeWeight
        style.hasFill = canvas.hasFill
        style.hasStroke = canvas.hasStroke
        style.material = canvas3D.currentMaterial
        return style
    }
}
