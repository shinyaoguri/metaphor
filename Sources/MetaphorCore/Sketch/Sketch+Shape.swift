// MARK: - Retained Shape API

extension Sketch {

    // MARK: - Shape Creation

    /// ``ShapeKind`` からリテインドシェイプを作成します。
    ///
    /// ```swift
    /// let box = createShape(.box(width: 1, height: 1, depth: 1))
    /// let circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 100))
    /// let group = createShape(.group)
    /// ```
    public func createShape(_ kind: ShapeKind) -> MShape {
        context.createShape(kind)
    }

    /// カスタムジオメトリ用の空のリテインドシェイプを作成します。
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

    /// リテインドシェイプを原点に描画します。
    public func shape(_ s: MShape) {
        context.shape(s)
    }

    /// リテインドシェイプを指定位置に描画します。
    public func shape(_ s: MShape, _ x: Float, _ y: Float) {
        context.shape(s, x, y)
    }

    /// リテインドシェイプを指定位置・サイズで描画します。
    public func shape(_ s: MShape, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.shape(s, x, y, w, h)
    }
}
