import Metal
import simd

// MARK: - Rect / Ellipse / Image Mode

/// Defines how coordinates are interpreted for `rect()` calls.
public enum RectMode: Sendable {
    /// Interprets x, y as the top-left corner and w, h as width and height (default).
    case corner
    /// Interprets x, y as the top-left corner and w, h as the bottom-right corner coordinates.
    case corners
    /// Interprets x, y as the center and w, h as width and height.
    case center
    /// Interprets x, y as the center and w, h as half-width and half-height.
    case radius
}

/// Defines how coordinates are interpreted for `ellipse()` calls.
public enum EllipseMode: Sendable {
    /// Interprets x, y as the center and w, h as width and height (default).
    case center
    /// Interprets x, y as the center and w, h as radii.
    case radius
    /// Interprets x, y as the top-left corner and w, h as width and height.
    case corner
    /// Interprets x, y as the top-left corner and w, h as the bottom-right corner coordinates.
    case corners
}

/// Defines how coordinates are interpreted for `image()` calls.
public enum ImageMode: Sendable {
    /// Interprets x, y as the top-left corner (default).
    case corner
    /// Interprets x, y as the center.
    case center
    /// Interprets x, y as the top-left corner and w, h as the bottom-right corner coordinates.
    case corners
}

/// Specifies the drawing mode for `arc()` calls.
public enum ArcMode: Sendable {
    /// Draws the arc only without connecting the endpoints.
    case open
    /// Connects the endpoints with a straight line.
    case chord
    /// Draws lines from the endpoints to the center, forming a pie shape.
    case pie
}

// MARK: - Stroke Cap / Join

/// Specifies the style applied to the endpoints of strokes.
public enum StrokeCap: Sendable {
    /// Applies a rounded cap to stroke endpoints (default).
    case round
    /// Applies a square cap that extends by half the stroke weight beyond the endpoint.
    case square
    /// Applies no extension beyond the endpoint.
    case butt
}

/// Specifies the style applied to the joints between connected stroke segments.
public enum StrokeJoin: Sendable {
    /// Joins segments with a sharp corner (default).
    case miter
    /// Joins segments with a flat bevel.
    case bevel
    /// Joins segments with a rounded arc.
    case round
}

// MARK: - Gradient Axis

/// Specifies the direction of a gradient fill.
public enum GradientAxis: Sendable {
    /// Applies the gradient from top to bottom.
    case vertical
    /// Applies the gradient from left to right.
    case horizontal
    /// Applies the gradient diagonally from the top-left to the bottom-right.
    case diagonal
}

// MARK: - Shape Mode

/// Specifies the primitive type used with `beginShape()`.
public enum ShapeMode: Sendable {
    /// Draws an arbitrary polygon (default).
    case polygon
    /// Draws a set of individual points.
    case points
    /// Draws pairs of vertices as separate line segments.
    case lines
    /// Draws groups of three vertices as individual triangles.
    case triangles
    /// Draws vertices as a triangle strip.
    case triangleStrip
    /// Draws vertices as a triangle fan.
    case triangleFan
}

/// Specifies whether a shape is closed when calling `endShape()`.
public enum CloseMode: Sendable {
    /// Leaves the shape open without connecting the last vertex to the first.
    case open
    /// Closes the shape by connecting the last vertex to the first.
    case close
}

// MARK: - Errors

/// Represents errors that can occur during Canvas2D operations.
public enum Canvas2DError: Error {
    /// Indicates that a Metal buffer could not be created.
    case bufferCreationFailed
}
