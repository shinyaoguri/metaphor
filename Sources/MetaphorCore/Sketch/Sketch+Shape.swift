// MARK: - Retained Shape API

extension Sketch {

    // MARK: - Shape Creation

    /// Create a retained shape from a ``ShapeKind``.
    ///
    /// ```swift
    /// let box = createShape(.box(width: 1, height: 1, depth: 1))
    /// let circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 100))
    /// let group = createShape(.group)
    /// ```
    public func createShape(_ kind: ShapeKind) -> MShape {
        context.createShape(kind)
    }

    /// Create an empty retained shape for custom geometry.
    ///
    /// ```swift
    /// let s = createShape()
    /// s.beginShape()
    /// s.vertex(0, 0)
    /// s.vertex(100, 0)
    /// s.vertex(50, 80)
    /// s.endShape(.close)
    /// ```
    public func createShape() -> MShape {
        context.createShape()
    }

    // MARK: - Shape Display

    /// Draw a retained shape at the origin.
    public func shape(_ s: MShape) {
        context.shape(s)
    }

    /// Draw a retained shape at the given position.
    public func shape(_ s: MShape, _ x: Float, _ y: Float) {
        context.shape(s, x, y)
    }

    /// Draw a retained shape at the given position and size.
    public func shape(_ s: MShape, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.shape(s, x, y, w, h)
    }
}
