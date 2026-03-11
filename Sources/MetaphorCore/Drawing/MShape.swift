import Metal
import simd

// MARK: - ShapeKind

/// Define the type and creation parameters of a retained shape.
///
/// Used with ``MShape`` to specify what geometry the shape represents.
/// Primitives carry their parameters inline; custom shapes use `.path2D` / `.path3D`.
public enum ShapeKind: Sendable {
    /// A group container that holds child shapes.
    case group

    // MARK: 2D Primitives
    /// A rectangle defined by position and size.
    case rect(x: Float, y: Float, width: Float, height: Float)
    /// An ellipse defined by center and size.
    case ellipse(x: Float, y: Float, width: Float, height: Float)
    /// A triangle defined by three corner points.
    case triangle(x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float)
    /// A quadrilateral defined by four corner points.
    case quad(x1: Float, y1: Float, x2: Float, y2: Float,
              x3: Float, y3: Float, x4: Float, y4: Float)
    /// An arc defined by center, size, angle range, and closing mode.
    case arc(x: Float, y: Float, width: Float, height: Float,
             start: Float, stop: Float, mode: ArcMode)
    /// A line segment between two points.
    case line(x1: Float, y1: Float, x2: Float, y2: Float)
    /// A single point.
    case point(x: Float, y: Float)

    // MARK: 3D Primitives
    /// A box with width, height, and depth.
    case box(width: Float, height: Float, depth: Float)
    /// A UV sphere with radius and tessellation detail.
    case sphere(radius: Float, detail: Int = 24)
    /// A flat plane with width and height.
    case plane(width: Float, height: Float)
    /// A cylinder with radius, height, and tessellation detail.
    case cylinder(radius: Float, height: Float, detail: Int = 24)
    /// A cone with radius, height, and tessellation detail.
    case cone(radius: Float, height: Float, detail: Int = 24)
    /// A torus with ring radius, tube radius, and tessellation detail.
    case torus(ringRadius: Float, tubeRadius: Float, detail: Int = 24)

    // MARK: Custom Geometry
    /// A custom 2D shape defined via `beginShape`/`vertex`/`endShape`.
    case path2D
    /// A custom 3D shape defined via `beginShape`/`vertex`/`endShape`.
    case path3D

    /// Whether this kind represents custom geometry (path2D or path3D).
    var isPath: Bool {
        switch self {
        case .path2D, .path3D: return true
        default: return false
        }
    }

    /// Whether this shape kind represents 3D geometry.
    public var is3D: Bool {
        switch self {
        case .box, .sphere, .plane, .cylinder, .cone, .torus, .path3D:
            return true
        case .group:
            return false  // group dimensionality depends on children
        default:
            return false
        }
    }
}

// MARK: - ShapeVertex2D

/// A vertex in a retained 2D shape, with optional per-vertex color and UV coordinates.
public struct ShapeVertex2D: Sendable {
    /// Position in 2D space.
    public var position: SIMD2<Float>
    /// Per-vertex color override. When nil, the shape's fill color is used.
    public var color: SIMD4<Float>?
    /// Texture coordinates. When nil, no texture mapping is applied.
    public var uv: SIMD2<Float>?

    public init(position: SIMD2<Float>, color: SIMD4<Float>? = nil, uv: SIMD2<Float>? = nil) {
        self.position = position
        self.color = color
        self.uv = uv
    }
}

// MARK: - ShapeVertex3D

/// A vertex in a retained 3D shape, with normal, optional color, and UV coordinates.
public struct ShapeVertex3D: Sendable {
    /// Position in 3D space.
    public var position: SIMD3<Float>
    /// Vertex normal for lighting calculations.
    public var normal: SIMD3<Float>
    /// Per-vertex color override. When nil, the shape's fill color is used.
    public var color: SIMD4<Float>?
    /// Texture coordinates. When nil, no texture mapping is applied.
    public var uv: SIMD2<Float>?

    public init(position: SIMD3<Float>, normal: SIMD3<Float> = SIMD3(0, 1, 0),
                color: SIMD4<Float>? = nil, uv: SIMD2<Float>? = nil) {
        self.position = position
        self.normal = normal
        self.color = color
        self.uv = uv
    }
}

// MARK: - ShapeStyle

/// A snapshot of visual style properties captured when a shape is created.
///
/// Used internally by ``MShape`` to store fill, stroke, and material state.
/// When `styleEnabled` is true on the shape, this style is applied during drawing;
/// when false, the sketch's current style is used instead.
public struct ShapeStyle {
    /// Fill color (RGBA, 0-1 range).
    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    /// Stroke color (RGBA, 0-1 range).
    public var strokeColor: SIMD4<Float> = SIMD4(0, 0, 0, 1)
    /// Stroke line weight in pixels.
    public var strokeWeight: Float = 1.0
    /// Whether fill is enabled.
    public var hasFill: Bool = true
    /// Whether stroke is enabled.
    public var hasStroke: Bool = true
    /// Tint color for textured shapes.
    public var tintColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    /// Whether tint is applied.
    public var hasTint: Bool = false
    /// 3D material properties. Nil for 2D-only shapes.
    var material: Material3D?

    /// Create a default style.
    public init() {}
}

// MARK: - MShape

/// A retained-mode shape that stores geometry, style, and transforms for efficient reuse.
///
/// Create shapes with ``Sketch/createShape(_:)`` or ``Sketch/createShape()``,
/// then draw them with ``Sketch/shape(_:)``.
///
/// ```swift
/// // In setup():
/// let star = createShape()
/// star.beginShape()
/// star.fill(.yellow)
/// star.noStroke()
/// for i in 0..<10 {
///     let angle = Float(i) * Float.pi / 5
///     let r: Float = (i % 2 == 0) ? 100 : 40
///     star.vertex(cos(angle) * r, sin(angle) * r)
/// }
/// star.endShape(.close)
///
/// // In draw():
/// shape(star, width / 2, height / 2)
/// star.rotate(0.01)
/// ```
@MainActor
public final class MShape {

    // MARK: - Identity

    /// An optional name for identifying this shape in a hierarchy.
    public var name: String?

    /// The Metal device used for GPU resource creation.
    let device: MTLDevice

    // MARK: - Kind & Dimensionality

    /// The kind of shape this instance represents.
    public internal(set) var kind: ShapeKind

    /// Whether this shape contains 3D geometry.
    ///
    /// For groups, returns true if any child is 3D.
    public var is3D: Bool {
        switch kind {
        case .group:
            return children.contains { $0.is3D }
        default:
            return kind.is3D
        }
    }

    // MARK: - Style

    /// The style snapshot captured at creation time.
    public var capturedStyle: ShapeStyle

    /// Whether the shape's own style is applied during drawing.
    /// When false, the sketch's current style is used instead.
    public private(set) var styleEnabled: Bool = true

    /// Texture assigned to this shape.
    public var texture: MTLTexture?

    // MARK: - Per-Shape Transform

    /// The accumulated 2D transform matrix for this shape.
    /// Modified by `translate`, `rotate`, `scale`, and reset by `resetMatrix`.
    public var localTransform2D: float3x3 = float3x3(1)

    /// The accumulated 3D transform matrix for this shape.
    /// Modified by `translate`, `rotate`, `rotateX/Y/Z`, `scale`, and reset by `resetMatrix`.
    public var localTransform3D: float4x4 = .identity

    // MARK: - Hierarchy

    /// Child shapes (for group shapes).
    public private(set) var children: [MShape] = []

    /// Weak reference to the parent shape.
    weak var parent: MShape?

    // MARK: - 2D Custom Geometry (path2D)

    /// Vertices for a custom 2D shape.
    var vertices2D: [ShapeVertex2D] = []

    /// Ranges within `vertices2D` that define contour holes.
    var contourRanges: [Range<Int>] = []

    /// The shape drawing mode for 2D custom shapes.
    var shapeMode2D: ShapeMode = .polygon

    /// Whether the 2D custom shape is closed.
    var closeMode2D: CloseMode = .open

    // MARK: - 3D Custom Geometry (path3D)

    /// Vertices for a custom 3D shape.
    var vertices3D: [ShapeVertex3D] = []

    /// The shape drawing mode for 3D custom shapes.
    var shapeMode3D: ShapeMode = .polygon

    /// Whether the 3D custom shape is closed.
    var closeMode3D: CloseMode = .open

    // MARK: - Geometry Cache

    /// Cached tessellated triangles for path2D fill (three SIMD2 per triangle).
    var cachedTriangles2D: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)]?

    /// Cached stroke outline points for path2D stroke.
    var cachedStrokeOutline2D: [(Float, Float)]?

    /// Cached Mesh for 3D custom shapes (path3D).
    var cachedMesh3D: Mesh?

    /// Cached Mesh for 3D primitives (box, sphere, etc.).
    var primitiveMesh3D: Mesh?

    /// Whether the geometry has been modified since last cache build.
    var isDirty: Bool = true

    // MARK: - Shape Building State

    /// Whether beginShape() has been called and endShape() has not yet been called.
    var isRecording: Bool = false

    /// The pending normal for the next 3D vertex.
    var pendingNormal3D: SIMD3<Float>?

    /// Tracks whether we're inside a contour definition.
    var isInContour: Bool = false

    /// The start index of the current contour in vertices2D.
    var contourStartIndex: Int = 0

    // MARK: - Initialization

    /// Create a new shape with the given kind and captured style.
    ///
    /// - Parameters:
    ///   - device: The Metal device for GPU resources.
    ///   - kind: The type of shape to create.
    ///   - style: The initial style snapshot.
    init(device: MTLDevice, kind: ShapeKind, style: ShapeStyle = ShapeStyle()) {
        self.device = device
        self.kind = kind
        self.capturedStyle = style
    }

    // MARK: - Style Modification

    /// Set the fill color of this shape.
    public func setFill(_ color: Color) {
        capturedStyle.fillColor = color.simd
        capturedStyle.hasFill = true
    }

    /// Enable or disable fill on this shape.
    public func setFill(_ enabled: Bool) {
        capturedStyle.hasFill = enabled
    }

    /// Set the stroke color of this shape.
    public func setStroke(_ color: Color) {
        capturedStyle.strokeColor = color.simd
        capturedStyle.hasStroke = true
    }

    /// Enable or disable stroke on this shape.
    public func setStroke(_ enabled: Bool) {
        capturedStyle.hasStroke = enabled
    }

    /// Set the stroke weight of this shape.
    public func setStrokeWeight(_ weight: Float) {
        capturedStyle.strokeWeight = weight
    }

    /// Set the texture of this shape.
    public func setTexture(_ img: MImage) {
        self.texture = img.texture
    }

    /// Set the tint color for textured rendering.
    public func setTint(_ color: Color) {
        capturedStyle.tintColor = color.simd
        capturedStyle.hasTint = true
    }

    /// Disable the shape's own style, using the sketch's current style when drawn.
    public func disableStyle() {
        styleEnabled = false
    }

    /// Enable the shape's own style (default behavior).
    public func enableStyle() {
        styleEnabled = true
    }

    // MARK: - Transform (Accumulated)

    /// Translate the shape in 2D.
    public func translate(_ x: Float, _ y: Float) {
        var t = float3x3(1)
        t[2][0] = x
        t[2][1] = y
        localTransform2D = localTransform2D * t
    }

    /// Translate the shape in 3D.
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        localTransform3D = localTransform3D * float4x4(translation: SIMD3(x, y, z))
    }

    /// Rotate the shape in 2D (radians).
    public func rotate(_ angle: Float) {
        let c = cos(angle), s = sin(angle)
        var r = float3x3(1)
        r[0][0] = c; r[0][1] = s
        r[1][0] = -s; r[1][1] = c
        localTransform2D = localTransform2D * r
    }

    /// Rotate the shape around the X axis (radians).
    public func rotateX(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationX: angle)
    }

    /// Rotate the shape around the Y axis (radians).
    public func rotateY(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationY: angle)
    }

    /// Rotate the shape around the Z axis (radians).
    public func rotateZ(_ angle: Float) {
        localTransform3D = localTransform3D * float4x4(rotationZ: angle)
    }

    /// Scale the shape uniformly in 2D.
    public func scale(_ s: Float) {
        var m = float3x3(1)
        m[0][0] = s; m[1][1] = s
        localTransform2D = localTransform2D * m
    }

    /// Scale the shape non-uniformly in 2D.
    public func scale(_ sx: Float, _ sy: Float) {
        var m = float3x3(1)
        m[0][0] = sx; m[1][1] = sy
        localTransform2D = localTransform2D * m
    }

    /// Scale the shape non-uniformly in 3D.
    public func scale(_ sx: Float, _ sy: Float, _ sz: Float) {
        localTransform3D = localTransform3D * float4x4(scale: SIMD3(sx, sy, sz))
    }

    /// Reset the shape's transform to identity.
    public func resetMatrix() {
        localTransform2D = float3x3(1)
        localTransform3D = .identity
    }

    // MARK: - Hierarchy

    /// Add a child shape to this group.
    ///
    /// - Parameter child: The child shape to add. Removes from previous parent if any.
    public func addChild(_ child: MShape) {
        if let oldParent = child.parent {
            oldParent.children.removeAll { $0 === child }
        }
        child.parent = self
        children.append(child)
    }

    /// Get a child shape by index.
    ///
    /// - Parameter index: The zero-based index.
    /// - Returns: The child shape, or nil if the index is out of range.
    public func getChild(_ index: Int) -> MShape? {
        guard index >= 0 && index < children.count else { return nil }
        return children[index]
    }

    /// Get a child shape by name (breadth-first search).
    ///
    /// - Parameter name: The name to search for.
    /// - Returns: The first child with the matching name, or nil.
    public func getChild(_ name: String) -> MShape? {
        for child in children {
            if child.name == name { return child }
        }
        for child in children {
            if let found = child.getChild(name) { return found }
        }
        return nil
    }

    /// The number of direct children.
    public var childCount: Int { children.count }

    // MARK: - Vertex Access

    /// The total number of vertices in this shape.
    ///
    /// For custom shapes, returns the vertex count. For primitives, returns 0.
    /// For groups, returns the sum of all children's vertex counts.
    public var vertexCount: Int {
        switch kind {
        case .path2D:
            return vertices2D.count
        case .path3D:
            return vertices3D.count
        case .group:
            return children.reduce(0) { $0 + $1.vertexCount }
        default:
            return 0
        }
    }

    /// Get a vertex position by index.
    ///
    /// For 2D shapes, the z component is 0.
    /// - Parameter index: The zero-based vertex index.
    /// - Returns: The vertex position as a 3-component vector, or nil if out of range.
    public func getVertex(_ index: Int) -> SIMD3<Float>? {
        switch kind {
        case .path2D:
            guard index >= 0 && index < vertices2D.count else { return nil }
            let p = vertices2D[index].position
            return SIMD3(p.x, p.y, 0)
        case .path3D:
            guard index >= 0 && index < vertices3D.count else { return nil }
            return vertices3D[index].position
        default:
            return nil
        }
    }

    /// Set a vertex position by index (2D).
    ///
    /// Marks the shape as dirty, triggering re-tessellation on next draw.
    /// - Parameters:
    ///   - index: The zero-based vertex index.
    ///   - x: The new x coordinate.
    ///   - y: The new y coordinate.
    public func setVertex(_ index: Int, _ x: Float, _ y: Float) {
        guard case .path2D = kind, index >= 0 && index < vertices2D.count else { return }
        vertices2D[index].position = SIMD2(x, y)
        invalidateCache()
    }

    /// Set a vertex position by index (3D).
    ///
    /// Marks the shape as dirty, triggering mesh rebuild on next draw.
    /// - Parameters:
    ///   - index: The zero-based vertex index.
    ///   - x: The new x coordinate.
    ///   - y: The new y coordinate.
    ///   - z: The new z coordinate.
    public func setVertex(_ index: Int, _ x: Float, _ y: Float, _ z: Float) {
        guard case .path3D = kind, index >= 0 && index < vertices3D.count else { return }
        vertices3D[index].position = SIMD3(x, y, z)
        invalidateCache()
    }

    // MARK: - Cache Invalidation

    /// Mark the geometry cache as invalid, forcing rebuild on next draw.
    func invalidateCache() {
        isDirty = true
        cachedTriangles2D = nil
        cachedStrokeOutline2D = nil
        cachedMesh3D = nil
    }
}
