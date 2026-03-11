extension SketchContext {

    // MARK: - 2D Shapes

    /// Draws a rectangle.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.rect(x, y, w, h)
    }

    /// Draws a rounded rectangle with a uniform corner radius.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - r: The corner radius.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        canvas.rect(x, y, w, h, r)
    }

    /// Draws a rounded rectangle with individual corner radii.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - tl: The top-left corner radius.
    ///   - tr: The top-right corner radius.
    ///   - br: The bottom-right corner radius.
    ///   - bl: The bottom-left corner radius.
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        canvas.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// Draws a rectangle filled with a linear gradient.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - c1: The start color.
    ///   - c2: The end color.
    ///   - axis: The gradient direction (default `.vertical`).
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        canvas.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// Draws a radial gradient.
    /// - Parameters:
    ///   - cx: The center x-coordinate.
    ///   - cy: The center y-coordinate.
    ///   - radius: The gradient radius.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the edge.
    ///   - segments: The number of segments (default 36).
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        canvas.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// Draws an ellipse.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.ellipse(x, y, w, h)
    }

    /// Draws a circle.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - diameter: The circle diameter.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        canvas.circle(x, y, diameter)
    }

    /// Draws a square.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - size: The side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        canvas.square(x, y, size)
    }

    /// Draws a quadrilateral defined by four corner points.
    /// - Parameters:
    ///   - x1: The x-coordinate of the first vertex.
    ///   - y1: The y-coordinate of the first vertex.
    ///   - x2: The x-coordinate of the second vertex.
    ///   - y2: The y-coordinate of the second vertex.
    ///   - x3: The x-coordinate of the third vertex.
    ///   - y3: The y-coordinate of the third vertex.
    ///   - x4: The x-coordinate of the fourth vertex.
    ///   - y4: The y-coordinate of the fourth vertex.
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Draws a line between two points.
    /// - Parameters:
    ///   - x1: The start x-coordinate.
    ///   - y1: The start y-coordinate.
    ///   - x2: The end x-coordinate.
    ///   - y2: The end y-coordinate.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        canvas.line(x1, y1, x2, y2)
    }

    /// Draws a triangle defined by three vertices.
    /// - Parameters:
    ///   - x1: The x-coordinate of the first vertex.
    ///   - y1: The y-coordinate of the first vertex.
    ///   - x2: The x-coordinate of the second vertex.
    ///   - y2: The y-coordinate of the second vertex.
    ///   - x3: The x-coordinate of the third vertex.
    ///   - y3: The y-coordinate of the third vertex.
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        canvas.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// Draws a polygon from an array of coordinate tuples.
    /// - Parameter points: An array of (x, y) coordinate tuples.
    public func polygon(_ points: [(Float, Float)]) {
        canvas.polygon(points)
    }

    /// Draws a polygon from an array of Vec2 points.
    /// - Parameter points: An array of Vec2 points.
    public func polygon(_ points: [Vec2]) {
        canvas.polygon(points.map { ($0.x, $0.y) })
    }

    /// Draws an arc.
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - w: The width of the bounding ellipse.
    ///   - h: The height of the bounding ellipse.
    ///   - startAngle: The starting angle in radians.
    ///   - stopAngle: The ending angle in radians.
    ///   - mode: The arc drawing mode (default `.open`).
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        canvas.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// Draws a cubic Bezier curve.
    /// - Parameters:
    ///   - x1: The start point x-coordinate.
    ///   - y1: The start point y-coordinate.
    ///   - cx1: The first control point x-coordinate.
    ///   - cy1: The first control point y-coordinate.
    ///   - cx2: The second control point x-coordinate.
    ///   - cy2: The second control point y-coordinate.
    ///   - x2: The end point x-coordinate.
    ///   - y2: The end point y-coordinate.
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// Draws a single point.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func point(_ x: Float, _ y: Float) {
        canvas.point(x, y)
    }

    // MARK: - Custom Shapes (beginShape / endShape)

    /// Begins recording a vertex-based custom shape.
    /// - Parameter mode: The shape drawing mode (default `.polygon`).
    public func beginShape(_ mode: ShapeMode = .polygon) {
        canvas.beginShape(mode)
    }

    /// Adds a vertex to the current shape.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func vertex(_ x: Float, _ y: Float) {
        canvas.vertex(x, y)
    }

    /// Adds a cubic Bezier vertex with control points and an endpoint.
    /// - Parameters:
    ///   - cx1: The first control point x-coordinate.
    ///   - cy1: The first control point y-coordinate.
    ///   - cx2: The second control point x-coordinate.
    ///   - cy2: The second control point y-coordinate.
    ///   - x: The endpoint x-coordinate.
    ///   - y: The endpoint y-coordinate.
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Adds a Catmull-Rom spline vertex.
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func curveVertex(_ x: Float, _ y: Float) {
        canvas.curveVertex(x, y)
    }

    /// Sets the number of subdivisions for curve segments.
    /// - Parameter n: The subdivision count.
    public func curveDetail(_ n: Int) {
        canvas.curveDetail(n)
    }

    /// Sets the tightness of Catmull-Rom curves.
    /// - Parameter t: The tightness value.
    public func curveTightness(_ t: Float) {
        canvas.curveTightness(t)
    }

    /// Begins recording a contour (hole) within the current shape.
    public func beginContour() {
        canvas.beginContour()
    }

    /// Ends the current contour (hole) recording.
    public func endContour() {
        canvas.endContour()
    }

    /// Adds a vertex with a per-vertex color (2D).
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        canvas.vertex(x, y, color)
    }

    /// Adds a vertex with UV texture coordinates (2D).
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - u: The U texture coordinate.
    ///   - v: The V texture coordinate.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        canvas.vertex(x, y, u, v)
    }

    /// Ends the current shape recording and draws the shape.
    /// - Parameter close: Whether to close the shape (default `.open`).
    public func endShape(_ close: CloseMode = .open) {
        canvas.endShape(close)
    }

    // MARK: - Clipping

    /// Begin clipping subsequent draws to the specified rectangle.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the clip region.
    ///   - y: The y-coordinate of the clip region.
    ///   - w: The width of the clip region.
    ///   - h: The height of the clip region.
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.beginClip(x, y, w, h)
    }

    /// End the current clip region and restore the previous one.
    public func endClip() {
        canvas.endClip()
    }
}
