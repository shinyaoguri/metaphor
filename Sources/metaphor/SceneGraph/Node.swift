import Metal
import simd

/// Represent a node in a hierarchical scene graph.
///
/// Each ``Node`` has a local transform defined by ``position``, ``rotation``
/// (Euler angles in radians), and ``scale``. Transforms are composed
/// hierarchically: a child's ``worldTransform`` is its parent's world
/// transform multiplied by its own ``localTransform``.
///
/// Nodes can optionally hold a ``mesh`` for rendering and/or an ``onDraw``
/// callback for custom drawing logic. Use ``SceneRenderer`` to traverse and
/// render the tree with a ``Canvas3D``.
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

    /// The local rotation of the node as Euler angles (in radians, XYZ order).
    public var rotation: SIMD3<Float> = .zero       // Euler angles (radians)

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

    /// Compute the local transform matrix from position, rotation, and scale.
    ///
    /// The transform is composed as T * Rz * Ry * Rx * S.
    ///
    /// - Returns: The 4x4 local transform matrix.
    public var localTransform: float4x4 {
        // T * Rz * Ry * Rx * S
        let t = float4x4(translation: position)
        let rx = float4x4(rotationX: rotation.x)
        let ry = float4x4(rotationY: rotation.y)
        let rz = float4x4(rotationZ: rotation.z)
        let s = float4x4(scale: scale)
        return t * rz * ry * rx * s
    }

    /// Compute the world transform by recursively combining parent transforms.
    ///
    /// - Returns: The 4x4 world transform matrix.
    public var worldTransform: float4x4 {
        if let parent = parent {
            return parent.worldTransform * localTransform
        }
        return localTransform
    }

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
}
