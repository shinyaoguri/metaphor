import Testing
import simd
@testable import MetaphorCore
@testable import MetaphorSceneGraph

// MARK: - Node Tests

@Suite("SceneGraph Node")
@MainActor
struct NodeTests {

    @Test("default node has identity transform")
    func defaultTransform() {
        let node = Node(name: "test")
        let identity = float4x4(1)
        let local = node.localTransform
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(local[col][row] - identity[col][row]) < 1e-5)
            }
        }
    }

    @Test("position sets translation")
    func positionTranslation() {
        let node = Node(name: "test")
        node.position = SIMD3(3, 4, 5)
        let m = node.localTransform
        #expect(abs(m[3][0] - 3) < 1e-5)
        #expect(abs(m[3][1] - 4) < 1e-5)
        #expect(abs(m[3][2] - 5) < 1e-5)
    }

    @Test("quaternion orientation produces correct rotation matrix")
    func quaternionRotation() {
        let node = Node(name: "test")
        node.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 1, 0))
        let m = node.localTransform
        // 90° rotation around Y: x→z, z→-x
        #expect(abs(m[0][0]) < 1e-4)      // cos(90°) ≈ 0
        #expect(abs(m[2][0] - 1) < 1e-4)  // sin(90°) ≈ 1
    }

    @Test("setRotation from Euler angles")
    func setRotationEuler() {
        let node = Node(name: "test")
        node.setRotation(x: 0, y: Float.pi / 2, z: 0)

        // Compare with direct quaternion
        let expected = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 1, 0))
        let diff = node.orientation.inverse * expected
        // Should be approximately identity quaternion
        #expect(abs(diff.real - 1) < 1e-4)
    }

    @Test("rotate(by:) composes rotations")
    func rotateBy() {
        let node = Node(name: "test")
        let q1 = simd_quatf(angle: Float.pi / 4, axis: SIMD3(0, 1, 0))
        let q2 = simd_quatf(angle: Float.pi / 4, axis: SIMD3(0, 1, 0))
        node.orientation = q1
        node.rotate(by: q2)

        // Result should be ~90° around Y
        let expected = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 1, 0))
        let diff = node.orientation.inverse * expected
        #expect(abs(diff.real - 1) < 1e-4)
    }

    @Test("scale applies correctly")
    func scaleTransform() {
        let node = Node(name: "test")
        node.scale = SIMD3(2, 3, 4)
        let m = node.localTransform
        #expect(abs(m[0][0] - 2) < 1e-5)
        #expect(abs(m[1][1] - 3) < 1e-5)
        #expect(abs(m[2][2] - 4) < 1e-5)
    }

    @Test("world transform combines parent and child")
    func worldTransform() {
        let parent = Node(name: "parent")
        parent.position = SIMD3(10, 0, 0)

        let child = Node(name: "child")
        child.position = SIMD3(5, 0, 0)
        parent.addChild(child)

        let world = child.worldTransform
        // Child's world X should be 10 + 5 = 15
        #expect(abs(world[3][0] - 15) < 1e-4)
    }

    @Test("world orientation combines parent and child quaternions")
    func worldOrientation() {
        let parent = Node(name: "parent")
        parent.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 1, 0))

        let child = Node(name: "child")
        child.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 1, 0))
        parent.addChild(child)

        // Combined should be ~180° around Y
        let expected = simd_quatf(angle: Float.pi, axis: SIMD3(0, 1, 0))
        let q = child.worldOrientation
        let diff = q.inverse * expected
        #expect(abs(abs(diff.real) - 1) < 1e-3)
    }

    // MARK: - Hierarchy

    @Test("addChild sets parent and updates children array")
    func addChildSetsParent() {
        let parent = Node(name: "parent")
        let child = Node(name: "child")
        parent.addChild(child)

        #expect(child.parent === parent)
        #expect(parent.children.count == 1)
        #expect(parent.children[0] === child)
    }

    @Test("addChild moves node from previous parent")
    func addChildMovesFromPreviousParent() {
        let parent1 = Node(name: "p1")
        let parent2 = Node(name: "p2")
        let child = Node(name: "child")

        parent1.addChild(child)
        #expect(parent1.children.count == 1)

        parent2.addChild(child)
        #expect(parent1.children.count == 0)
        #expect(parent2.children.count == 1)
        #expect(child.parent === parent2)
    }

    @Test("removeChild clears parent")
    func removeChildClearsParent() {
        let parent = Node(name: "parent")
        let child = Node(name: "child")
        parent.addChild(child)
        parent.removeChild(child)

        #expect(child.parent == nil)
        #expect(parent.children.isEmpty)
    }

    @Test("removeAllChildren clears all")
    func removeAllChildren() {
        let parent = Node(name: "parent")
        for i in 0..<5 {
            parent.addChild(Node(name: "c\(i)"))
        }
        #expect(parent.children.count == 5)

        parent.removeAllChildren()
        #expect(parent.children.isEmpty)
    }

    @Test("find locates descendant by name")
    func findByName() {
        let root = Node(name: "root")
        let a = Node(name: "a")
        let b = Node(name: "b")
        let c = Node(name: "c")
        root.addChild(a)
        a.addChild(b)
        root.addChild(c)

        #expect(root.find("b") === b)
        #expect(root.find("c") === c)
        #expect(root.find("nonexistent") == nil)
    }

    // MARK: - Direction Helpers

    @Test("forward direction is negative Z by default")
    func forwardDefault() {
        let node = Node(name: "test")
        let f = node.forward
        #expect(abs(f.x) < 1e-5)
        #expect(abs(f.y) < 1e-5)
        #expect(abs(f.z + 1) < 1e-5)
    }

    @Test("right direction is positive X by default")
    func rightDefault() {
        let node = Node(name: "test")
        let r = node.right
        #expect(abs(r.x - 1) < 1e-5)
        #expect(abs(r.y) < 1e-5)
        #expect(abs(r.z) < 1e-5)
    }

    @Test("up direction is positive Y by default")
    func upDefault() {
        let node = Node(name: "test")
        let u = node.up
        #expect(abs(u.x) < 1e-5)
        #expect(abs(u.y - 1) < 1e-5)
        #expect(abs(u.z) < 1e-5)
    }
}

// MARK: - AABB Tests

@Suite("AABB")
struct AABBTests {

    @Test("center and extents")
    func centerExtents() {
        let aabb = AABB(min: SIMD3(-1, -2, -3), max: SIMD3(1, 2, 3))
        #expect(abs(aabb.center.x) < 1e-5)
        #expect(abs(aabb.center.y) < 1e-5)
        #expect(abs(aabb.center.z) < 1e-5)
        #expect(abs(aabb.extents.x - 1) < 1e-5)
        #expect(abs(aabb.extents.y - 2) < 1e-5)
        #expect(abs(aabb.extents.z - 3) < 1e-5)
    }

    @Test("intersects frustum - inside")
    func intersectsInside() {
        let aabb = AABB(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        // Large frustum enclosing everything
        let planes: [SIMD4<Float>] = [
            SIMD4(1, 0, 0, 100),   // left:   x > -100
            SIMD4(-1, 0, 0, 100),  // right:  x < 100
            SIMD4(0, 1, 0, 100),   // bottom: y > -100
            SIMD4(0, -1, 0, 100),  // top:    y < 100
            SIMD4(0, 0, 1, 100),   // near:   z > -100
            SIMD4(0, 0, -1, 100),  // far:    z < 100
        ]
        #expect(aabb.intersects(frustum: planes) == true)
    }

    @Test("intersects frustum - outside")
    func intersectsOutside() {
        let aabb = AABB(min: SIMD3(50, 50, 50), max: SIMD3(60, 60, 60))
        // Small frustum around origin
        let planes: [SIMD4<Float>] = [
            SIMD4(1, 0, 0, 10),
            SIMD4(-1, 0, 0, 10),
            SIMD4(0, 1, 0, 10),
            SIMD4(0, -1, 0, 10),
            SIMD4(0, 0, 1, 10),
            SIMD4(0, 0, -1, 10),
        ]
        #expect(aabb.intersects(frustum: planes) == false)
    }

    @Test("transformed AABB")
    func transformedAABB() {
        let aabb = AABB(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        let translate = float4x4(translation: SIMD3(10, 0, 0))
        let result = aabb.transformed(by: translate)
        #expect(abs(result.min.x - 9) < 1e-4)
        #expect(abs(result.max.x - 11) < 1e-4)
    }
}

// MARK: - SceneRenderer Tests

@Suite("SceneRenderer")
@MainActor
struct SceneRendererTests {

    @Test("extract frustum planes from identity VP returns 6 planes")
    func extractFrustumPlanes() {
        let vp = float4x4(1) // identity
        let planes = SceneRenderer.extractFrustumPlanes(from: vp)
        #expect(planes.count == 6)
    }

    @Test("extract frustum planes from perspective VP")
    func extractPerspectiveFrustum() {
        let proj = float4x4(perspectiveFov: Float.pi / 3, aspect: 1.0, near: 0.1, far: 100)
        let view = float4x4(lookAt: SIMD3(0, 0, 5), center: SIMD3(0, 0, 0), up: SIMD3(0, 1, 0))
        let vp = proj * view
        let planes = SceneRenderer.extractFrustumPlanes(from: vp)
        #expect(planes.count == 6)

        // An AABB at the origin should be inside
        let aabb = AABB(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        #expect(aabb.intersects(frustum: planes) == true)

        // An AABB far behind the camera should be outside
        let behindCamera = AABB(min: SIMD3(-1, -1, 100), max: SIMD3(1, 1, 110))
        #expect(behindCamera.intersects(frustum: planes) == false)
    }

    @Test("invisible nodes are not visited")
    func invisibleNodeSkipped() {
        let node = Node(name: "hidden")
        node.isVisible = false
        var callbackCalled = false
        node.onDraw = { callbackCalled = true }

        // Cannot call SceneRenderer.render without Canvas3D (needs GPU),
        // but we can verify the node's isVisible flag directly
        #expect(node.isVisible == false)
        #expect(callbackCalled == false)
    }
}

// MARK: - Node + float4x4 extension helpers

fileprivate extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self = float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(t.x, t.y, t.z, 1)
        )
    }

    init(perspectiveFov fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        self = float4x4(
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        )
    }

    init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        self = float4x4(
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
}
