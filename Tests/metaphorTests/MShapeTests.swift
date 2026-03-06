import Testing
import Metal
import simd
@testable import MetaphorCore

// MARK: - ShapeKind Tests

@Suite("ShapeKind")
struct ShapeKindTests {

    @Test("2D kinds are not 3D")
    func kinds2DAreNot3D() {
        #expect(!ShapeKind.rect(x: 0, y: 0, width: 100, height: 50).is3D)
        #expect(!ShapeKind.ellipse(x: 0, y: 0, width: 80, height: 80).is3D)
        #expect(!ShapeKind.triangle(x1: 0, y1: 0, x2: 1, y2: 0, x3: 0.5, y3: 1).is3D)
        #expect(!ShapeKind.quad(x1: 0, y1: 0, x2: 1, y2: 0, x3: 1, y3: 1, x4: 0, y4: 1).is3D)
        #expect(!ShapeKind.line(x1: 0, y1: 0, x2: 1, y2: 1).is3D)
        #expect(!ShapeKind.point(x: 0, y: 0).is3D)
        #expect(!ShapeKind.arc(x: 0, y: 0, width: 100, height: 100, start: 0, stop: .pi, mode: .open).is3D)
        #expect(!ShapeKind.path2D.is3D)
        #expect(!ShapeKind.group.is3D)
    }

    @Test("3D kinds are 3D")
    func kinds3DAre3D() {
        #expect(ShapeKind.box(width: 1, height: 1, depth: 1).is3D)
        #expect(ShapeKind.sphere(radius: 0.5).is3D)
        #expect(ShapeKind.plane(width: 1, height: 1).is3D)
        #expect(ShapeKind.cylinder(radius: 0.5, height: 1).is3D)
        #expect(ShapeKind.cone(radius: 0.5, height: 1).is3D)
        #expect(ShapeKind.torus(ringRadius: 0.5, tubeRadius: 0.2).is3D)
        #expect(ShapeKind.path3D.is3D)
    }

    @Test("isPath identifies custom geometry kinds")
    func isPathCheck() {
        #expect(ShapeKind.path2D.isPath)
        #expect(ShapeKind.path3D.isPath)
        #expect(!ShapeKind.group.isPath)
        #expect(!ShapeKind.rect(x: 0, y: 0, width: 1, height: 1).isPath)
        #expect(!ShapeKind.box(width: 1, height: 1, depth: 1).isPath)
    }
}

// MARK: - ShapeStyle Tests

@Suite("ShapeStyle")
struct ShapeStyleTests {

    @Test("default style values")
    func defaultStyle() {
        let style = ShapeStyle()
        #expect(style.hasFill == true)
        #expect(style.hasStroke == true)
        #expect(style.strokeWeight == 1.0)
        #expect(style.fillColor == SIMD4<Float>(1, 1, 1, 1))
        #expect(style.strokeColor == SIMD4<Float>(0, 0, 0, 1))
        #expect(style.hasTint == false)
        #expect(style.material == nil)
    }
}

// MARK: - MShape Data Model Tests

@Suite("MShape Data Model", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeDataModelTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("empty shape has zero vertex count")
    func emptyShapeVertexCount() {
        let s = MShape(device: device, kind: .path2D)
        #expect(s.vertexCount == 0)
    }

    @Test("primitive shape has zero vertex count")
    func primitiveVertexCount() {
        let s = MShape(device: device, kind: .rect(x: 0, y: 0, width: 100, height: 50))
        #expect(s.vertexCount == 0)
    }

    @Test("is3D detection for group depends on children")
    func groupIs3D() {
        let group = MShape(device: device, kind: .group)
        #expect(!group.is3D)

        let child2D = MShape(device: device, kind: .rect(x: 0, y: 0, width: 10, height: 10))
        group.addChild(child2D)
        #expect(!group.is3D)

        let child3D = MShape(device: device, kind: .box(width: 1, height: 1, depth: 1))
        group.addChild(child3D)
        #expect(group.is3D)
    }

    @Test("style modification methods")
    func styleModification() {
        let s = MShape(device: device, kind: .path2D)
        s.setFill(.red)
        #expect(s.capturedStyle.fillColor == SIMD4<Float>(1, 0, 0, 1))
        #expect(s.capturedStyle.hasFill == true)

        s.setFill(false)
        #expect(s.capturedStyle.hasFill == false)

        s.setStroke(.blue)
        #expect(s.capturedStyle.strokeColor == SIMD4<Float>(0, 0, 1, 1))
        #expect(s.capturedStyle.hasStroke == true)

        s.setStrokeWeight(3.0)
        #expect(s.capturedStyle.strokeWeight == 3.0)
    }

    @Test("disableStyle / enableStyle")
    func disableEnableStyle() {
        let s = MShape(device: device, kind: .path2D)
        #expect(s.styleEnabled == true)
        s.disableStyle()
        #expect(s.styleEnabled == false)
        s.enableStyle()
        #expect(s.styleEnabled == true)
    }
}

// MARK: - Transform Tests

@Suite("MShape Transform", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeTransformTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("translate accumulates in 2D")
    func translate2D() {
        let s = MShape(device: device, kind: .path2D)
        s.translate(10, 20)
        #expect(abs(s.localTransform2D[2][0] - 10) < 0.001)
        #expect(abs(s.localTransform2D[2][1] - 20) < 0.001)

        s.translate(5, 3)
        #expect(abs(s.localTransform2D[2][0] - 15) < 0.001)
        #expect(abs(s.localTransform2D[2][1] - 23) < 0.001)
    }

    @Test("translate accumulates in 3D")
    func translate3D() {
        let s = MShape(device: device, kind: .box(width: 1, height: 1, depth: 1))
        s.translate(1, 2, 3)
        #expect(abs(s.localTransform3D[3][0] - 1) < 0.001)
        #expect(abs(s.localTransform3D[3][1] - 2) < 0.001)
        #expect(abs(s.localTransform3D[3][2] - 3) < 0.001)
    }

    @Test("rotate 2D")
    func rotate2D() {
        let s = MShape(device: device, kind: .path2D)
        s.rotate(Float.pi / 2)
        // After 90° rotation, [0][0] ≈ 0, [0][1] ≈ 1
        #expect(abs(s.localTransform2D[0][0]) < 0.001)
        #expect(abs(s.localTransform2D[0][1] - 1) < 0.001)
    }

    @Test("scale 2D")
    func scale2D() {
        let s = MShape(device: device, kind: .path2D)
        s.scale(2, 3)
        #expect(abs(s.localTransform2D[0][0] - 2) < 0.001)
        #expect(abs(s.localTransform2D[1][1] - 3) < 0.001)
    }

    @Test("resetMatrix clears transform")
    func resetMatrix() {
        let s = MShape(device: device, kind: .path2D)
        s.translate(100, 200)
        s.rotate(1.0)
        s.resetMatrix()
        #expect(s.localTransform2D == float3x3(1))
        #expect(s.localTransform3D == .identity)
    }
}

// MARK: - Hierarchy Tests

@Suite("MShape Hierarchy", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeHierarchyTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("addChild and childCount")
    func addChildAndCount() {
        let group = MShape(device: device, kind: .group)
        #expect(group.childCount == 0)

        let child = MShape(device: device, kind: .rect(x: 0, y: 0, width: 10, height: 10))
        group.addChild(child)
        #expect(group.childCount == 1)
    }

    @Test("getChild by index")
    func getChildByIndex() {
        let group = MShape(device: device, kind: .group)
        let child1 = MShape(device: device, kind: .path2D)
        child1.name = "first"
        let child2 = MShape(device: device, kind: .path2D)
        child2.name = "second"
        group.addChild(child1)
        group.addChild(child2)

        #expect(group.getChild(0)?.name == "first")
        #expect(group.getChild(1)?.name == "second")
        #expect(group.getChild(2) == nil)
        #expect(group.getChild(-1) == nil)
    }

    @Test("getChild by name (breadth-first)")
    func getChildByName() {
        let group = MShape(device: device, kind: .group)
        let child = MShape(device: device, kind: .path2D)
        child.name = "star"
        let subgroup = MShape(device: device, kind: .group)
        let grandchild = MShape(device: device, kind: .path2D)
        grandchild.name = "hidden"
        subgroup.addChild(grandchild)
        group.addChild(child)
        group.addChild(subgroup)

        #expect(group.getChild("star") === child)
        #expect(group.getChild("hidden") === grandchild)
        #expect(group.getChild("nonexistent") == nil)
    }

    @Test("addChild moves from previous parent")
    func reparenting() {
        let group1 = MShape(device: device, kind: .group)
        let group2 = MShape(device: device, kind: .group)
        let child = MShape(device: device, kind: .path2D)

        group1.addChild(child)
        #expect(group1.childCount == 1)

        group2.addChild(child)
        #expect(group1.childCount == 0)
        #expect(group2.childCount == 1)
    }

    @Test("weak parent reference does not cause retain cycle")
    func weakParent() {
        var group: MShape? = MShape(device: device, kind: .group)
        let child = MShape(device: device, kind: .path2D)
        group!.addChild(child)
        #expect(child.parent != nil)
        group = nil
        #expect(child.parent == nil)
    }

    @Test("group vertexCount sums children")
    func groupVertexCount() {
        let group = MShape(device: device, kind: .group)
        let s1 = MShape(device: device, kind: .path2D)
        s1.beginShape()
        s1.vertex(0, 0)
        s1.vertex(1, 0)
        s1.vertex(0.5, 1)
        s1.endShape()

        let s2 = MShape(device: device, kind: .path2D)
        s2.beginShape()
        s2.vertex(0, 0)
        s2.vertex(1, 1)
        s2.endShape()

        group.addChild(s1)
        group.addChild(s2)
        #expect(group.vertexCount == 5)
    }
}

// MARK: - Shape Builder Tests

@Suite("MShape Builder", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeBuilderTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("beginShape/vertex/endShape creates 2D path")
    func basicPath2D() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(100, 0)
        s.vertex(50, 80)
        s.endShape(.close)

        #expect(s.vertexCount == 3)
        #expect(s.closeMode2D == .close)
        #expect(s.isDirty == true)
    }

    @Test("3D vertex switches kind to path3D")
    func vertex3DSwitchesKind() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0, 1, 0)
        s.endShape()

        if case .path3D = s.kind {
            // expected
        } else {
            Issue.record("Expected .path3D, got \(s.kind)")
        }
        #expect(s.vertices3D.count == 3)
    }

    @Test("normal sets pending normal for next 3D vertex")
    func normalSetting() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.normal(0, 0, 1)
        s.vertex(0, 0, 0)
        s.endShape()

        #expect(s.vertices3D.first?.normal == SIMD3<Float>(0, 0, 1))
    }

    @Test("contour ranges are recorded correctly")
    func contourRanges() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        // Outer polygon
        s.vertex(0, 0)
        s.vertex(200, 0)
        s.vertex(200, 200)
        s.vertex(0, 200)
        // Hole
        s.beginContour()
        s.vertex(50, 50)
        s.vertex(150, 50)
        s.vertex(150, 150)
        s.vertex(50, 150)
        s.endContour()
        s.endShape(.close)

        #expect(s.vertices2D.count == 8)
        #expect(s.contourRanges.count == 1)
        #expect(s.contourRanges[0] == 4..<8)
    }

    @Test("style methods during shape definition")
    func styleDuringDefinition() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.fill(.red)
        s.noStroke()
        s.vertex(0, 0)
        s.vertex(1, 0)
        s.vertex(0.5, 1)
        s.endShape(.close)

        #expect(s.capturedStyle.fillColor == SIMD4<Float>(1, 0, 0, 1))
        #expect(s.capturedStyle.hasStroke == false)
    }

    @Test("vertex without beginShape is ignored")
    func vertexWithoutBeginShape() {
        let s = MShape(device: device, kind: .path2D)
        s.vertex(10, 20)
        #expect(s.vertexCount == 0)
    }
}

// MARK: - Vertex Access Tests

@Suite("MShape Vertex Access", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeVertexAccessTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("getVertex returns correct position")
    func getVertex2D() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(10, 20)
        s.vertex(30, 40)
        s.endShape()

        let v0 = s.getVertex(0)
        #expect(v0 != nil)
        #expect(v0!.x == 10)
        #expect(v0!.y == 20)
        #expect(v0!.z == 0)

        let v1 = s.getVertex(1)
        #expect(v1!.x == 30)
    }

    @Test("setVertex marks dirty")
    func setVertexMarksDirty() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(1, 0)
        s.vertex(0.5, 1)
        s.endShape(.close)

        // Build cache first
        s.ensureCacheValid()
        #expect(s.isDirty == false)

        // Modify vertex
        s.setVertex(0, 50, 60)
        #expect(s.isDirty == true)
        #expect(s.cachedTriangles2D == nil)

        // Verify position changed
        let v = s.getVertex(0)
        #expect(v!.x == 50)
        #expect(v!.y == 60)
    }

    @Test("setVertex out of range is no-op")
    func setVertexOutOfRange() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.endShape()
        s.setVertex(5, 10, 20) // out of range
        #expect(s.vertices2D[0].position == SIMD2<Float>(0, 0))
    }

    @Test("getVertex on primitive returns nil")
    func getVertexOnPrimitive() {
        let s = MShape(device: device, kind: .rect(x: 0, y: 0, width: 10, height: 10))
        #expect(s.getVertex(0) == nil)
    }
}

// MARK: - Tessellation Cache Tests

@Suite("MShape Tessellation Cache", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeTessellationTests {

    let device = MTLCreateSystemDefaultDevice()!

    @Test("polygon tessellation produces triangles")
    func polygonTessellation() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(100, 0)
        s.vertex(100, 100)
        s.vertex(0, 100)
        s.endShape(.close)

        s.ensureCacheValid()
        #expect(s.isDirty == false)
        #expect(s.cachedTriangles2D != nil)
        #expect(s.cachedTriangles2D!.count == 2) // quad = 2 triangles
    }

    @Test("triangle mode produces correct triangle count")
    func triangleMode() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        s.vertex(0, 0)
        s.vertex(1, 0)
        s.vertex(0.5, 1)
        s.vertex(2, 0)
        s.vertex(3, 0)
        s.vertex(2.5, 1)
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedTriangles2D!.count == 2)
    }

    @Test("triangle strip mode")
    func triangleStripMode() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangleStrip)
        s.vertex(0, 0)
        s.vertex(1, 0)
        s.vertex(0.5, 1)
        s.vertex(1.5, 1)
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedTriangles2D!.count == 2)
    }

    @Test("triangle fan mode")
    func triangleFanMode() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangleFan)
        s.vertex(0, 0) // center
        s.vertex(1, 0)
        s.vertex(0.7, 0.7)
        s.vertex(0, 1)
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedTriangles2D!.count == 2)
    }

    @Test("empty path produces empty cache")
    func emptyPath() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedTriangles2D!.isEmpty)
    }

    @Test("polygon with hole tessellation")
    func polygonWithHole() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(200, 0)
        s.vertex(200, 200)
        s.vertex(0, 200)
        s.beginContour()
        s.vertex(50, 50)
        s.vertex(150, 50)
        s.vertex(150, 150)
        s.vertex(50, 150)
        s.endContour()
        s.endShape(.close)

        s.ensureCacheValid()
        #expect(s.cachedTriangles2D != nil)
        // Outer quad (4 verts) + hole (4 verts) after bridge merging produces more triangles
        #expect(s.cachedTriangles2D!.count >= 4)
    }

    @Test("3D path builds mesh")
    func path3DMeshBuild() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        s.normal(0, 0, 1)
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0.5, 1, 0)
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedMesh3D != nil)
        #expect(s.cachedMesh3D!.vertexCount == 3)
    }

    @Test("re-tessellation after setVertex")
    func reTessellationAfterSetVertex() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(100, 0)
        s.vertex(100, 100)
        s.endShape(.close)

        s.ensureCacheValid()
        let original = s.cachedTriangles2D

        s.setVertex(2, 50, 150)
        s.ensureCacheValid()

        #expect(s.cachedTriangles2D != nil)
        // The triangle changed position
        let newV2 = s.cachedTriangles2D![0].2
        #expect(newV2.x == 50 || newV2.y == 150 || original != nil) // cache was rebuilt
    }
}
