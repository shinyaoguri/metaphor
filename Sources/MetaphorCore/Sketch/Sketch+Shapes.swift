// MARK: - 2D Transform & Shapes

extension Sketch {

    // MARK: 2D Transform Stack

    /// Save the current transform and style state onto the stack.
    public func push() {
        context.push()
    }

    /// Restore the most recently saved transform and style state from the stack.
    public func pop() {
        context.pop()
    }

    /// Save the current style state (fill, stroke, etc.) onto the stack.
    public func pushStyle() {
        context.pushStyle()
    }

    /// Restore the most recently saved style state from the stack.
    public func popStyle() {
        context.popStyle()
    }

    /// Apply a 2D translation to the current transform.
    ///
    /// - Parameters:
    ///   - x: The horizontal translation amount.
    ///   - y: The vertical translation amount.
    public func translate(_ x: Float, _ y: Float) {
        context.translate(x, y)
    }

    /// Apply a 2D rotation to the current transform.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) {
        context.rotate(angle)
    }

    /// Apply a non-uniform 2D scale to the current transform.
    ///
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) {
        context.scale(sx, sy)
    }

    /// Apply a uniform 2D scale to the current transform.
    ///
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) {
        context.scale(s)
    }

    // MARK: 2D Shapes

    /// Draw a rectangle.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.rect(x, y, w, h)
    }

    /// Draw a rounded rectangle with a uniform corner radius.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - r: The corner radius.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        context.rect(x, y, w, h, r)
    }

    /// Draw a rounded rectangle with individual corner radii.
    ///
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
        context.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// Draw a linear gradient rectangle.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width.
    ///   - h: The height.
    ///   - c1: The start color.
    ///   - c2: The end color.
    ///   - axis: The gradient direction.
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        context.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// Draw a radial gradient circle.
    ///
    /// - Parameters:
    ///   - cx: The center x-coordinate.
    ///   - cy: The center y-coordinate.
    ///   - radius: The outer radius.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the edge.
    ///   - segments: The number of segments for smoothness.
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        context.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// Draw an ellipse.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - w: The width (horizontal diameter).
    ///   - h: The height (vertical diameter).
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.ellipse(x, y, w, h)
    }

    /// Draw a circle.
    ///
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - diameter: The diameter of the circle.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        context.circle(x, y, diameter)
    }

    /// Draw a square.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - size: The side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        context.square(x, y, size)
    }

    /// Draw a quadrilateral defined by four corner points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first corner.
    ///   - y1: The y-coordinate of the first corner.
    ///   - x2: The x-coordinate of the second corner.
    ///   - y2: The y-coordinate of the second corner.
    ///   - x3: The x-coordinate of the third corner.
    ///   - y3: The y-coordinate of the third corner.
    ///   - x4: The x-coordinate of the fourth corner.
    ///   - y4: The y-coordinate of the fourth corner.
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Draw a line between two points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the start point.
    ///   - y1: The y-coordinate of the start point.
    ///   - x2: The x-coordinate of the end point.
    ///   - y2: The y-coordinate of the end point.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        context.line(x1, y1, x2, y2)
    }

    /// Draw a triangle defined by three corner points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first corner.
    ///   - y1: The y-coordinate of the first corner.
    ///   - x2: The x-coordinate of the second corner.
    ///   - y2: The y-coordinate of the second corner.
    ///   - x3: The x-coordinate of the third corner.
    ///   - y3: The y-coordinate of the third corner.
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        context.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// Draw a polygon from an array of coordinate tuples.
    ///
    /// - Parameter points: The polygon vertices as `(x, y)` tuples.
    public func polygon(_ points: [(Float, Float)]) {
        context.polygon(points)
    }

    /// Draw a polygon from an array of ``Vec2`` points.
    ///
    /// - Parameter points: The polygon vertices.
    public func polygon(_ points: [Vec2]) {
        context.polygon(points)
    }

    /// Draw an arc.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the arc center.
    ///   - y: The y-coordinate of the arc center.
    ///   - w: The width of the arc's bounding ellipse.
    ///   - h: The height of the arc's bounding ellipse.
    ///   - startAngle: The start angle in radians.
    ///   - stopAngle: The stop angle in radians.
    ///   - mode: The arc drawing mode.
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        context.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// Draw a cubic Bezier curve.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the start point.
    ///   - y1: The y-coordinate of the start point.
    ///   - cx1: The x-coordinate of the first control point.
    ///   - cy1: The y-coordinate of the first control point.
    ///   - cx2: The x-coordinate of the second control point.
    ///   - cy2: The y-coordinate of the second control point.
    ///   - x2: The x-coordinate of the end point.
    ///   - y2: The y-coordinate of the end point.
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        context.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// Draw a single point.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func point(_ x: Float, _ y: Float) {
        context.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    /// Begin recording vertices for a custom shape.
    ///
    /// - Parameter mode: The shape mode (e.g., polygon, triangles, lines).
    public func beginShape(_ mode: ShapeMode = .polygon) {
        context.beginShape(mode)
    }

    /// Add a 2D vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func vertex(_ x: Float, _ y: Float) {
        context.vertex(x, y)
    }

    /// Add a 2D vertex with a per-vertex color to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - color: The vertex color.
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        context.vertex(x, y, color)
    }

    /// Add a 2D vertex with texture coordinates to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - u: The horizontal texture coordinate.
    ///   - v: The vertical texture coordinate.
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, u, v)
    }

    /// Add a cubic Bezier vertex to the current shape.
    ///
    /// - Parameters:
    ///   - cx1: The x-coordinate of the first control point.
    ///   - cy1: The y-coordinate of the first control point.
    ///   - cx2: The x-coordinate of the second control point.
    ///   - cy2: The y-coordinate of the second control point.
    ///   - x: The x-coordinate of the anchor point.
    ///   - y: The y-coordinate of the anchor point.
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        context.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Add a Catmull-Rom spline vertex to the current shape.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    public func curveVertex(_ x: Float, _ y: Float) {
        context.curveVertex(x, y)
    }

    /// Set the number of segments used for curve interpolation.
    ///
    /// - Parameter n: The curve detail level.
    public func curveDetail(_ n: Int) {
        context.curveDetail(n)
    }

    /// Set the tightness of Catmull-Rom spline curves.
    ///
    /// - Parameter t: The tightness value (0 = default, 1 = straight lines).
    public func curveTightness(_ t: Float) {
        context.curveTightness(t)
    }

    /// Begin defining a contour (hole) within the current shape.
    public func beginContour() {
        context.beginContour()
    }

    /// End the current contour definition.
    public func endContour() {
        context.endContour()
    }

    /// Draw a Catmull-Rom spline curve through four points.
    ///
    /// - Parameters:
    ///   - x1: The x-coordinate of the first control point.
    ///   - y1: The y-coordinate of the first control point.
    ///   - x2: The x-coordinate of the start point.
    ///   - y2: The y-coordinate of the start point.
    ///   - x3: The x-coordinate of the end point.
    ///   - y3: The y-coordinate of the end point.
    ///   - x4: The x-coordinate of the second control point.
    ///   - y4: The y-coordinate of the second control point.
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// Finish recording the current shape and draw it.
    ///
    /// - Parameter close: Whether to close the shape by connecting the last vertex to the first.
    public func endShape(_ close: CloseMode = .open) {
        context.endShape(close)
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
        context.beginClip(x, y, w, h)
    }

    /// End the current clip region and restore the previous one.
    public func endClip() {
        context.endClip()
    }
}
