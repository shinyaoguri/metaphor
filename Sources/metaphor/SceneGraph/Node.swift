import Metal
import simd

/// シーングラフのノード
@MainActor
public final class Node {
    public var name: String
    public var position: SIMD3<Float> = .zero
    public var rotation: SIMD3<Float> = .zero       // Euler angles (radians)
    public var scale: SIMD3<Float> = SIMD3(1, 1, 1)
    public var isVisible: Bool = true
    public var mesh: Mesh?
    public var fillColor: Color?
    public var onDraw: (() -> Void)?

    public private(set) weak var parent: Node?
    public private(set) var children: [Node] = []

    public init(name: String = "") {
        self.name = name
    }

    public var localTransform: float4x4 {
        // T * Rz * Ry * Rx * S
        let t = float4x4(translation: position)
        let rx = float4x4(rotationX: rotation.x)
        let ry = float4x4(rotationY: rotation.y)
        let rz = float4x4(rotationZ: rotation.z)
        let s = float4x4(scale: scale)
        return t * rz * ry * rx * s
    }

    public var worldTransform: float4x4 {
        if let parent = parent {
            return parent.worldTransform * localTransform
        }
        return localTransform
    }

    public func addChild(_ child: Node) {
        child.parent?.removeChild(child)
        child.parent = self
        children.append(child)
    }

    public func removeChild(_ child: Node) {
        children.removeAll { $0 === child }
        child.parent = nil
    }

    public func find(_ name: String) -> Node? {
        if self.name == name { return self }
        for child in children {
            if let found = child.find(name) { return found }
        }
        return nil
    }
}
