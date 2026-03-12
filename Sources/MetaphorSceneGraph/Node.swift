import Metal
import MetaphorCore
import simd

/// An axis-aligned bounding box for frustum culling.
public struct AABB: Sendable {
    /// The minimum corner of the bounding box.
    public var min: SIMD3<Float>

    /// The maximum corner of the bounding box.
    public var max: SIMD3<Float>

    /// Create an AABB with the given minimum and maximum corners.
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// The center of the bounding box.
    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }

    /// The half-extents (half-size) along each axis.
    public var extents: SIMD3<Float> {
        (max - min) * 0.5
    }

    /// Test if this AABB is outside the given frustum planes.
    ///
    /// Each plane is represented as (nx, ny, nz, d) where the positive
    /// half-space is the visible side.
    ///
    /// - Parameter planes: An array of frustum planes (typically 6).
    /// - Returns: `true` if the AABB is at least partially inside the frustum.
    public func intersects(frustum planes: [SIMD4<Float>]) -> Bool {
        let c = center
        let e = extents
        for plane in planes {
            let n = SIMD3<Float>(plane.x, plane.y, plane.z)
            let d = plane.w
            let r = dot(e, abs(n))
            let s = dot(c, n) + d
            if s + r < 0 { return false }
        }
        return true
    }

    /// Transform this AABB by a 4x4 matrix, producing a new (larger) AABB.
    public func transformed(by matrix: float4x4) -> AABB {
        let corners: [SIMD3<Float>] = [
            SIMD3(min.x, min.y, min.z), SIMD3(max.x, min.y, min.z),
            SIMD3(min.x, max.y, min.z), SIMD3(max.x, max.y, min.z),
            SIMD3(min.x, min.y, max.z), SIMD3(max.x, min.y, max.z),
            SIMD3(min.x, max.y, max.z), SIMD3(max.x, max.y, max.z),
        ]
        var newMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var newMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in corners {
            let p = matrix * SIMD4<Float>(corner, 1.0)
            let p3 = SIMD3<Float>(p.x, p.y, p.z)
            newMin = pointwiseMin(newMin, p3)
            newMax = pointwiseMax(newMax, p3)
        }
        return AABB(min: newMin, max: newMax)
    }
}

/// Represent a node in a hierarchical scene graph.
///
/// Each ``Node`` has a local transform defined by ``position``, ``orientation``
/// (quaternion), and ``scale``. Transforms are composed hierarchically: a
/// child's ``worldTransform`` is its parent's world transform multiplied by its
/// own ``localTransform``.
///
/// Nodes can optionally hold a ``mesh`` for rendering and/or an ``onDraw``
/// callback for custom drawing logic. Use ``SceneRenderer`` to traverse and
/// render the tree with a `Canvas3D`.
///
/// ```swift
/// let root = Node(name: "root")
/// let child = Node(name: "cube")
/// child.mesh = cubeMesh
/// child.position = SIMD3(2, 0, 0)
/// root.addChild(child)
/// SceneRenderer.render(node: root, canvas: canvas)
/// ```
@MainActor
public final class Node {
    /// The name of this node, used for identification and lookup.
    public var name: String

    /// The local position of the node relative to its parent.
    public var position: SIMD3<Float> = .zero

    /// The local orientation of the node as a quaternion.
    public var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))

    /// The local scale of the node along each axis.
    public var scale: SIMD3<Float> = SIMD3(1, 1, 1)

    /// Indicate whether the node and its children should be rendered.
    public var isVisible: Bool = true

    /// The optional mesh to draw at this node's position.
    public var mesh: Mesh?

    /// The optional fill color applied to the mesh when rendering this node.
    public var fillColor: Color?

    /// An optional custom draw callback invoked during scene traversal.
    public var onDraw: (() -> Void)?

    /// The optional bounding box for frustum culling (in local space).
    public var bounds: AABB?

    /// The parent node, or `nil` if this is the root.
    public private(set) weak var parent: Node?

    /// The ordered list of child nodes.
    public private(set) var children: [Node] = []

    /// Create a new node with the given name.
    ///
    /// - Parameter name: The name for identification (defaults to an empty string).
    public init(name: String = "") {
        self.name = name
    }

    // MARK: - Transform

    /// Set the rotation from Euler angles (convenience).
    ///
    /// Composes as Rz * Ry * Rx (same order as the old Euler-based API).
    ///
    /// - Parameters:
    ///   - x: Rotation around the x-axis in radians.
    ///   - y: Rotation around the y-axis in radians.
    ///   - z: Rotation around the z-axis in radians.
    public func setRotation(x: Float = 0, y: Float = 0, z: Float = 0) {
        orientation = simd_quatf(angle: z, axis: SIMD3(0, 0, 1))
                    * simd_quatf(angle: y, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: x, axis: SIMD3(1, 0, 0))
    }

    /// Rotate the node by a quaternion relative to the current orientation.
    ///
    /// - Parameter rotation: The rotation to apply.
    public func rotate(by rotation: simd_quatf) {
        orientation = rotation * orientation
    }

    /// Compute the local transform matrix from position, orientation, and scale.
    ///
    /// The transform is composed as T * R * S.
    public var localTransform: float4x4 {
        let t = float4x4(translation: position)
        let r = float4x4(orientation)
        let s = float4x4(scale: scale)
        return t * r * s
    }

    /// Compute the world transform by recursively combining parent transforms.
    public var worldTransform: float4x4 {
        if let parent = parent {
            return parent.worldTransform * localTransform
        }
        return localTransform
    }

    /// The world-space bounding box, computed from the local bounds and world transform.
    public var worldBounds: AABB? {
        bounds?.transformed(by: worldTransform)
    }

    // MARK: - Hierarchy

    /// Add a child node to this node.
    ///
    /// If the child already has a parent, it is first removed from that parent.
    ///
    /// - Parameter child: The node to add as a child.
    public func addChild(_ child: Node) {
        child.parent?.removeChild(child)
        child.parent = self
        children.append(child)
    }

    /// Remove a child node from this node.
    ///
    /// - Parameter child: The child node to remove.
    public func removeChild(_ child: Node) {
        children.removeAll { $0 === child }
        child.parent = nil
    }

    /// Remove all children from this node.
    public func removeAllChildren() {
        for child in children {
            child.parent = nil
        }
        children.removeAll()
    }

    /// Search for a descendant node by name using depth-first traversal.
    ///
    /// - Parameter name: The name to search for.
    /// - Returns: The first node with a matching name, or `nil` if not found.
    public func find(_ name: String) -> Node? {
        if self.name == name { return self }
        for child in children {
            if let found = child.find(name) { return found }
        }
        return nil
    }

    // MARK: - Direction Helpers

    /// The forward direction vector in world space (negative Z).
    public var forward: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(0, 0, -1))
    }

    /// The right direction vector in world space (positive X).
    public var right: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(1, 0, 0))
    }

    /// The up direction vector in world space (positive Y).
    public var up: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(0, 1, 0))
    }

    /// The world-space orientation (combined parent + local quaternions).
    public var worldOrientation: simd_quatf {
        if let parent = parent {
            return parent.worldOrientation * orientation
        }
        return orientation
    }

    /// Make this node look at the given world-space target.
    ///
    /// - Parameters:
    ///   - target: The point to look at.
    ///   - worldUp: The world up direction (defaults to +Y).
    public func lookAt(_ target: SIMD3<Float>, worldUp: SIMD3<Float> = SIMD3(0, 1, 0)) {
        let worldPos = SIMD3<Float>(worldTransform.columns.3.x,
                                     worldTransform.columns.3.y,
                                     worldTransform.columns.3.z)
        let dir = normalize(target - worldPos)
        let forward = SIMD3<Float>(0, 0, -1)

        let dotVal = dot(forward, dir)
        if dotVal > 0.9999 {
            orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            return
        }
        if dotVal < -0.9999 {
            orientation = simd_quatf(angle: .pi, axis: worldUp)
            return
        }

        let axis = normalize(cross(forward, dir))
        let angle = acos(dotVal)
        var q = simd_quatf(angle: angle, axis: axis)

        // Remove parent rotation contribution
        if let parent = parent {
            q = parent.worldOrientation.inverse * q
        }
        orientation = q
    }
}
