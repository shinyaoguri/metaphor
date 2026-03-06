import Metal
import simd

/// Provide a 3D mesh whose vertices can be added and modified dynamically.
///
/// Offers functionality equivalent to openFrameworks' ofMesh or p5.js' p5.Geometry.
/// Whenever vertex data changes, the isDirty flag is set and GPU buffers
/// are automatically rebuilt at draw time.
///
/// ```swift
/// let mesh = createDynamicMesh()
/// mesh.addVertex(0, 0, 0)
/// mesh.addVertex(1, 0, 0)
/// mesh.addVertex(0.5, 1, 0)
/// mesh.addTriangle(0, 1, 2)
/// dynamicMesh(mesh)
/// ```
@MainActor
public final class DynamicMesh {
    private let device: MTLDevice
    private var vertices: [Vertex3D] = []
    private var indices: [UInt32] = []
    private var isDirty = true
    private var cachedVertexBuffer: MTLBuffer?
    private var cachedIndexBuffer: MTLBuffer?

    // Pending normal and color for the next vertex to be added
    private var pendingNormal: SIMD3<Float> = SIMD3(0, 1, 0)
    private var pendingColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Vertex Operations

    /// Add a vertex at the given position.
    public func addVertex(_ position: SIMD3<Float>) {
        vertices.append(Vertex3D(
            position: position,
            normal: pendingNormal,
            color: pendingColor
        ))
        isDirty = true
    }

    /// Add a vertex at the specified x, y, z coordinates.
    public func addVertex(_ x: Float, _ y: Float, _ z: Float) {
        addVertex(SIMD3(x, y, z))
    }

    /// Set the normal to be applied to the next added vertex.
    public func addNormal(_ normal: SIMD3<Float>) {
        pendingNormal = normal
    }

    /// Set the color to be applied to the next added vertex.
    public func addColor(_ color: Color) {
        pendingColor = color.simd
    }

    /// Set the color to be applied to the next added vertex using a SIMD4 value.
    public func addColor(_ color: SIMD4<Float>) {
        pendingColor = color
    }

    // MARK: - Index Operations

    /// Append a single index.
    public func addIndex(_ i: UInt32) {
        indices.append(i)
        isDirty = true
    }

    /// Append three indices forming a triangle.
    public func addTriangle(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) {
        indices.append(contentsOf: [i0, i1, i2])
        isDirty = true
    }

    // MARK: - Access & Modify

    /// Return the number of vertices.
    public var vertexCount: Int { vertices.count }

    /// Return the number of indices.
    public var indexCount: Int { indices.count }

    /// Return the position of the vertex at the given index.
    public func getVertex(_ index: Int) -> SIMD3<Float> {
        vertices[index].position
    }

    /// Set the position of the vertex at the given index.
    public func setVertex(_ index: Int, _ position: SIMD3<Float>) {
        vertices[index].position = position
        isDirty = true
    }

    /// Set the normal of the vertex at the given index.
    public func setNormal(_ index: Int, _ normal: SIMD3<Float>) {
        vertices[index].normal = normal
        isDirty = true
    }

    /// Set the color of the vertex at the given index.
    public func setColor(_ index: Int, _ color: SIMD4<Float>) {
        vertices[index].color = color
        isDirty = true
    }

    /// Remove all vertices and indices.
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        isDirty = true
    }

    // MARK: - Internal GPU Buffer Management

    /// Rebuild GPU buffers if the data has been modified.
    internal func ensureBuffers() {
        guard isDirty else { return }
        guard !vertices.isEmpty else {
            cachedVertexBuffer = nil
            cachedIndexBuffer = nil
            isDirty = false
            return
        }

        cachedVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex3D>.stride * vertices.count,
            options: .storageModeShared
        )

        if !indices.isEmpty {
            cachedIndexBuffer = device.makeBuffer(
                bytes: indices,
                length: MemoryLayout<UInt32>.stride * indices.count,
                options: .storageModeShared
            )
        } else {
            cachedIndexBuffer = nil
        }

        isDirty = false
    }

    /// Return the vertex buffer (valid after calling ensureBuffers).
    internal var vertexBuffer: MTLBuffer? { cachedVertexBuffer }

    /// Return the index buffer (valid after calling ensureBuffers).
    public var indexBuffer: MTLBuffer? { cachedIndexBuffer }
}
