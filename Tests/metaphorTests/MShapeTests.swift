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
        #expect(s.didWarnContourIn3D == false, "2D シェイプの contour は正しい使い方なので警告しない")
    }

    @Test("contour on a 3D shape warns instead of silently doing nothing")
    func contourIn3DWarns() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        // 外側の四角（3D 頂点なので kind は .path3D になる）
        s.vertex(0, 0, 0)
        s.vertex(200, 0, 0)
        s.vertex(200, 200, 0)
        s.vertex(0, 200, 0)
        // 穴を開けたつもりのコンター（3D では効かない）
        s.beginContour()
        s.vertex(50, 50, 0)
        s.vertex(150, 50, 0)
        s.vertex(150, 150, 0)
        s.endContour()
        s.endShape(.close)

        #expect(s.didWarnContourIn3D, "3D シェイプの beginContour() は黙って無視せず警告する")
        #expect(s.contourRanges.isEmpty, "3D 頂点は vertices2D に入らないのでコンター範囲もできない")
        #expect(s.isInContour == false, "3D では 2D 側のコンター記録状態を汚さない")
        #expect(s.contourStartIndex == 0)
    }

    @Test("contour opened before any vertex still warns on a 3D shape")
    func contourBeforeVertexIn3DWarns() {
        // beginContour() の時点では kind がまだ .path2D なので、endShape() 側の
        // 取りこぼし防止が効いていないと警告が出ない
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.beginContour()
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0, 1, 0)
        s.endContour()
        s.endShape(.close)

        #expect(s.didWarnContourIn3D, "頂点より先に開いたコンターでも 3D なら警告する")
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

    // MARK: - 3D ストロークジオメトリ（#735）
    //
    // ストロークは退化三角形 (a, b, b) の列で表す。ワイヤーフレーム描画（`triangleFillMode = .lines`）
    // が三角形の 3 辺を線で描くため、線分 a-b だけが残る。よって辺 1 本 = 頂点 3 つ。

    @Test("closed polygon strokes every edge including the closing one")
    func path3DStrokeClosedPolygon() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        for i in 0..<5 {
            s.vertex(Float(i), 0, 0)
        }
        s.endShape(.close)

        s.ensureCacheValid()
        let stroke = try #require(s.cachedStrokeMesh3D)
        #expect(stroke.vertexCount == 15)  // 5 辺（最後→最初を含む）
    }

    @Test("open polygon leaves the closing edge out")
    func path3DStrokeOpenPolygon() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        for i in 0..<5 {
            s.vertex(Float(i), 0, 0)
        }
        s.endShape()

        s.ensureCacheValid()
        let stroke = try #require(s.cachedStrokeMesh3D)
        #expect(stroke.vertexCount == 12)  // 4 辺
    }

    @Test("lines mode draws segments instead of a fill mesh")
    func path3DStrokeLinesMode() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.lines)
        for i in 0..<6 {
            s.vertex(Float(i), 0, 0)
        }
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedMesh3D == nil)  // 塗る面は無い
        let stroke = try #require(s.cachedStrokeMesh3D)
        #expect(stroke.vertexCount == 9)  // 3 本の線分
    }

    @Test("points mode draws a small triangle per vertex")
    func path3DStrokePointsMode() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.points)
        for i in 0..<4 {
            s.vertex(Float(i), 0, 0)
        }
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedMesh3D == nil)
        let stroke = try #require(s.cachedStrokeMesh3D)
        #expect(stroke.vertexCount == 12)  // 4 点 × 3 頂点
    }

    @Test("triangle modes keep the wireframe stroke (no outline mesh)")
    func path3DStrokeTriangleModes() {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0.5, 1, 0)
        s.endShape()

        s.ensureCacheValid()
        #expect(s.cachedMesh3D != nil)
        // 三角形系は塗りメッシュ自身のワイヤーフレームが辺を描くので、別メッシュは持たない
        #expect(s.cachedStrokeMesh3D == nil)
    }

    @Test("stroke mesh is rebuilt after setVertex")
    func path3DStrokeRebuiltAfterSetVertex() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0.5, 1, 0)
        s.endShape(.close)

        s.ensureCacheValid()
        let original = try #require(s.cachedStrokeMesh3D)

        s.setVertex(2, 0.5, 5, 0)
        #expect(s.cachedStrokeMesh3D == nil)  // 古い形のまま描き続けない

        s.ensureCacheValid()
        let rebuilt = try #require(s.cachedStrokeMesh3D)
        #expect(rebuilt !== original)
    }

    @Test("re-tessellation after setVertex")
    func reTessellationAfterSetVertex() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.vertex(0, 0)
        s.vertex(100, 0)
        s.vertex(100, 100)
        s.endShape(.close)

        s.ensureCacheValid()
        let original = try #require(s.cachedTriangles2D)

        s.setVertex(2, 50, 150)
        s.ensureCacheValid()

        let updated = try #require(s.cachedTriangles2D)
        // setVertex 後の再tessellation で、変更した頂点 (50,150) が反映されている。
        let updatedVerts = updated.flatMap { [$0.0, $0.1, $0.2] }
        #expect(updatedVerts.contains { abs($0.x - 50) < 0.001 && abs($0.y - 150) < 0.001 })
        // 変更前は (100,100) を含み、変更後は含まない（古いキャッシュを返していない）。
        let originalVerts = original.flatMap { [$0.0, $0.1, $0.2] }
        #expect(originalVerts.contains { abs($0.x - 100) < 0.001 && abs($0.y - 100) < 0.001 })
        #expect(!updatedVerts.contains { abs($0.x - 100) < 0.001 && abs($0.y - 100) < 0.001 })
    }
}

// MARK: - 面を作れない頂点数でも落ちない（#881）
//
// 頂点数はジェネラティブな組み立てで動的に決まるので、三角形 1 枚に足りない
// 頂点数（0〜2）は普通に起こる。塗る面が無いなら空メッシュ（3D は nil、2D は空配列）を
// 返すのが素直で、プロセスごと落ちてはいけない。
//
// `.triangleStrip` / `.triangleFan` の 3D 側は `0..<(count - 2)` / `1..<(count - 1)` を
// 直に組んでいたため、count == 1 で負幅の `Range` を作ってトラップしていた。

@Suite("MShape degenerate vertex counts", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeDegenerateVertexCountTests {

    let device = MTLCreateSystemDefaultDevice()!

    /// 三角形 1 枚に足りない頂点数（0〜2）を積んだ 3D シェイプ。
    private func make3D(_ mode: ShapeMode, vertexCount: Int) -> MShape {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(mode)
        for i in 0..<vertexCount {
            s.vertex(Float(i), 0, 0)
        }
        s.endShape()
        return s
    }

    @Test("3D triangle strip survives every vertex count below a full triangle",
          arguments: [0, 1, 2])
    func triangleStrip3DBelowThreshold(vertexCount: Int) {
        let s = make3D(.triangleStrip, vertexCount: vertexCount)
        s.ensureCacheValid()
        #expect(s.cachedMesh3D == nil)  // 塗る面は作れない
        #expect(s.isDirty == false)
    }

    @Test("3D triangle fan survives every vertex count below a full triangle",
          arguments: [0, 1, 2])
    func triangleFan3DBelowThreshold(vertexCount: Int) {
        let s = make3D(.triangleFan, vertexCount: vertexCount)
        s.ensureCacheValid()
        #expect(s.cachedMesh3D == nil)
        #expect(s.isDirty == false)
    }

    @Test("3D triangle strip still builds a mesh once three vertices are in")
    func triangleStrip3DAtThreshold() throws {
        let s = make3D(.triangleStrip, vertexCount: 3)
        s.ensureCacheValid()
        let mesh = try #require(s.cachedMesh3D)
        #expect(mesh.vertexCount == 3)
    }

    @Test("3D triangle fan still builds a mesh once three vertices are in")
    func triangleFan3DAtThreshold() throws {
        let s = make3D(.triangleFan, vertexCount: 3)
        s.ensureCacheValid()
        let mesh = try #require(s.cachedMesh3D)
        #expect(mesh.vertexCount == 3)
    }

    /// 2D 側は元から `guard count >= 3` を持つ。3D を直したあとも規則が 2 つに割れないよう固定する。
    @Test("2D triangle strip / fan stay empty below three vertices",
          arguments: [ShapeMode.triangleStrip, .triangleFan], [0, 1, 2])
    func triangleStripFan2DBelowThreshold(mode: ShapeMode, vertexCount: Int) throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(mode)
        for i in 0..<vertexCount {
            s.vertex(Float(i), 0)
        }
        s.endShape()

        s.ensureCacheValid()
        #expect(try #require(s.cachedTriangles2D).isEmpty)
    }
}

// MARK: - リテインドな 3D シェイプの法線自動計算（#738）
//
// `normal()` を書かないリテインド 3D シェイプは全頂点が既定の (0, 1, 0) のままで、
// 真横からライトが当たる面が真っ黒に沈んでいた（イミディエイト側は面法線を
// 自動計算するので、同じ形を書いても陰影が付く）。
//
// メッシュは `.storageModeShared` なので、CPU から頂点バッファを読んで固定できる。

@Suite("MShape 3D auto normals", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeAutoNormalTests {

    let device = MTLCreateSystemDefaultDevice()!

    /// 塗りメッシュの頂点法線を CPU 側で読み出す。
    private func fillNormals(_ s: MShape) throws -> [SIMD3<Float>] {
        s.ensureCacheValid()
        let mesh = try #require(s.cachedMesh3D)
        let base = mesh.vertexBuffer.contents().bindMemory(
            to: Vertex3D.self, capacity: mesh.vertexCount)
        return (0..<mesh.vertexCount).map { base[$0].normal }
    }

    @Test("normal() 無しの三角形は面法線を得る")
    func trianglesGetFaceNormal() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        // z = 0 平面の三角形。面法線は (0, 0, ±1) で、既定の (0, 1, 0) とは別物。
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(0, 1, 0)
        s.endShape()

        let normals = try fillNormals(s)
        #expect(normals.count == 3)
        for n in normals {
            #expect(abs(abs(n.z) - 1) < 0.001, "z 成分が ±1 の面法線: \(n)")
            #expect(abs(n.x) < 0.001 && abs(n.y) < 0.001, "x/y 成分は 0: \(n)")
        }
    }

    @Test("normal() 無しの polygon は面法線を得る")
    func polygonGetsFaceNormal() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        // z = 0 平面の五角形（#738 の再現に使った形）
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            s.vertex(cos(a), sin(a), 0)
        }
        s.endShape(.close)

        let normals = try fillNormals(s)
        #expect(normals.count == 5)
        for n in normals {
            #expect(abs(abs(n.z) - 1) < 0.001, "全頂点が面法線を持つ: \(n)")
        }
    }

    // 失敗系: `normal()` を明示したシェイプでは自動計算が働かず指定値が残る。
    @Test("normal() を明示したら自動計算は働かない")
    func explicitNormalWins() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        // リテインドの normal() は次の 1 頂点にしか効かないので毎回呼ぶ
        // （持続範囲がイミディエイトと非対称なのは #738 とは別件）。
        s.normal(1, 0, 0)
        s.vertex(0, 0, 0)
        s.normal(1, 0, 0)
        s.vertex(1, 0, 0)
        s.normal(1, 0, 0)
        s.vertex(0, 1, 0)
        s.endShape()

        let normals = try fillNormals(s)
        for n in normals {
            #expect(abs(n.x - 1) < 0.001 && abs(n.y) < 0.001 && abs(n.z) < 0.001,
                    "明示した (1, 0, 0) がそのまま残る: \(n)")
        }
    }

    // 境界値: 3 頂点が一直線に並ぶ退化三角形。外積が零ベクトルになるので
    // 正規化すると NaN になる。既定の (0, 1, 0) へ落ちること。
    @Test("退化した三角形は NaN にならず既定の法線へ落ちる")
    func degenerateTriangleFallsBack() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangles)
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(2, 0, 0)   // 一直線
        s.endShape()

        let normals = try fillNormals(s)
        for n in normals {
            #expect(!n.x.isNaN && !n.y.isNaN && !n.z.isNaN, "NaN を書き込まない: \(n)")
            #expect(abs(n.x) < 0.001 && abs(n.y - 1) < 0.001 && abs(n.z) < 0.001,
                    "既定の (0, 1, 0) へ落ちる: \(n)")
        }
    }

    // `.triangleStrip` は「3 頂点ごと」ではインデックスの topology に合わないため、
    // 後ろの頂点が既定のまま取り残される。組み上がったインデックス列から計算すれば
    // 全頂点に法線が付く（巻き方向の反転もインデックス構築側が補正済み）。
    @Test("triangleStrip は全頂点に法線が付く")
    func triangleStripCoversEveryVertex() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangleStrip)
        // z = 0 平面のジグザグ 5 頂点（3 頂点ごとの規則だと後ろ 2 頂点が漏れる）
        s.vertex(0, 0, 0)
        s.vertex(0, 1, 0)
        s.vertex(1, 0, 0)
        s.vertex(1, 1, 0)
        s.vertex(2, 0, 0)
        s.endShape()

        let normals = try fillNormals(s)
        #expect(normals.count == 5)
        for (i, n) in normals.enumerated() {
            #expect(abs(abs(n.z) - 1) < 0.001, "頂点 \(i) にも面法線が付く: \(n)")
        }
        // 巻き方向はインデックス構築側（i % 2 で入れ替え）が補正済みなので、
        // ストリップ全体で法線の向きが揃う。
        let first = normals[0]
        for (i, n) in normals.enumerated() {
            #expect(simd_dot(first, n) > 0.999, "頂点 \(i) の向きが先頭と揃う: \(n)")
        }
    }

    @Test("triangleFan は全頂点に法線が付く")
    func triangleFanCoversEveryVertex() throws {
        let s = MShape(device: device, kind: .path2D)
        s.beginShape(.triangleFan)
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.vertex(1, 1, 0)
        s.vertex(0, 1, 0)
        s.vertex(-1, 1, 0)
        s.endShape()

        let normals = try fillNormals(s)
        #expect(normals.count == 5)
        for (i, n) in normals.enumerated() {
            #expect(abs(abs(n.z) - 1) < 0.001, "頂点 \(i) にも面法線が付く: \(n)")
        }
    }
}

// MARK: - サイズ指定 shape() の状態汚染防止（#158）

@Suite("MShape Sized Draw", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeSizedDrawTests {

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
    }

    @Test("sized shape() does not overwrite the unsized primitive mesh")
    func sizedShapeNoPollution() throws {
        let ctx = try makeContext()
        let box = ctx.createShape(.box(width: 2, height: 2, depth: 2))

        // サイズなし描画で元寸法のメッシュが確定
        ctx.shape(box, 0, 0)
        let originalMesh = box.primitiveMesh3D
        #expect(originalMesh != nil)

        // サイズ指定描画は別スロット（sizedMesh3D）に入り、元メッシュは不変
        ctx.shape(box, 0, 0, 10, 20)
        #expect(box.primitiveMesh3D === originalMesh,
                "サイズ指定 shape() が primitiveMesh3D を上書きしない")
        #expect(box.sizedMesh3D != nil)

        // 同一寸法の再描画では sizedMesh3D を再利用（毎フレーム生成しない）
        let sizedMesh = box.sizedMesh3D
        ctx.shape(box, 0, 0, 10, 20)
        #expect(box.sizedMesh3D === sizedMesh)

        // その後のサイズなし描画も元メッシュのまま
        ctx.shape(box, 0, 0)
        #expect(box.primitiveMesh3D === originalMesh)
    }
}

// MARK: - Canvas3D プリミティブの単位メッシュキャッシュ（#158）

@Suite("Canvas3D Unit Mesh Cache", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DUnitMeshCacheTests {

    @Test("animated box dimensions do not create new meshes per frame")
    func boxDimensionAnimation() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas3D = try Canvas3D(renderer: renderer)

        // box(sin(t)*100) 相当: 毎回異なる寸法でもキャッシュエントリは 1 つ
        for i in 0..<50 {
            canvas3D.box(Float(i) * 1.7 + 1, Float(i) * 0.9 + 1, Float(i) * 2.3 + 1)
            canvas3D.sphere(Float(i) * 0.5 + 1)
        }
        // 単位メッシュ 2 種（box_unit / sphere_unit_24_12）だけがキャッシュされる
        #expect(canvas3D.meshCacheCountForTesting <= 2,
                "寸法アニメーションでメッシュキャッシュが増殖しない (count: \(canvas3D.meshCacheCountForTesting))")
    }
}

// MARK: - シェイプ定義中の fill(gray) / stroke(gray) が colorMode を通る（#853）
//
// `MShapeBuilder` の gray 版は `gray / 255` と α リテラル 1 を直に書いており、
// 本線（`CanvasStyleProtocol` の `colorModeConfig.toGray()`）と結果が食い違っていた。
// 同じ `fill(128)` が MShape の中と外で別の色になり、`colorMode(.rgb, 1.0)` では
// 差が最大（0.5 が 0.00196 = ほぼ黒）になる。

@Suite("MShape builder color mode", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MShapeBuilderColorModeTests {

    let device = MTLCreateSystemDefaultDevice()!

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        return SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
    }

    private func expectClose(
        _ actual: SIMD4<Float>, _ expected: SIMD4<Float>,
        _ label: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let d = abs(actual - expected)
        #expect(d.max() < 0.001, "\(label): got \(actual), want \(expected)",
                sourceLocation: sourceLocation)
    }

    // MARK: 既定（rgb 0-255）は今までどおり

    @Test("the default 0-255 range keeps its existing result")
    func defaultRangeUnchanged() throws {
        let ctx = try makeContext()
        let s = ctx.createShape()
        s.beginShape()
        s.fill(128)
        s.stroke(64)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, SIMD4(128 / 255, 128 / 255, 128 / 255, 1), "fill")
        expectClose(s.capturedStyle.strokeColor, SIMD4(64 / 255, 64 / 255, 64 / 255, 1), "stroke")
    }

    // MARK: colorMode のレンジを通る

    @Test("fill(gray) follows colorMode(.rgb, 1.0)")
    func fillFollowsUnitRange() throws {
        let ctx = try makeContext()
        ctx.colorMode(.rgb, 1.0)
        let s = ctx.createShape()
        s.beginShape()
        s.fill(0.5)
        s.endShape()

        // 直すまでは 0.5 / 255 = 0.00196（ほぼ黒）だった
        expectClose(s.capturedStyle.fillColor, SIMD4(0.5, 0.5, 0.5, 1), "fill")
        #expect(s.capturedStyle.hasFill)
    }

    @Test("stroke(gray) follows colorMode(.rgb, 1.0)")
    func strokeFollowsUnitRange() throws {
        let ctx = try makeContext()
        ctx.colorMode(.rgb, 1.0)
        let s = ctx.createShape()
        s.beginShape()
        s.stroke(0.25)
        s.endShape()

        expectClose(s.capturedStyle.strokeColor, SIMD4(0.25, 0.25, 0.25, 1), "stroke")
        #expect(s.capturedStyle.hasStroke)
    }

    @Test("gray is measured against max1, whatever the color space is")
    func grayUsesFirstChannelMax() throws {
        let ctx = try makeContext()
        ctx.colorMode(.hsb, 360, 100, 100, 1)
        let s = ctx.createShape()
        s.beginShape()
        s.fill(180)
        s.endShape()

        // toGray は space を見ず gray / max1 を取る（本線と同じ）
        expectClose(s.capturedStyle.fillColor, SIMD4(0.5, 0.5, 0.5, 1), "fill")
    }

    @Test("the shape and the sketch agree on the same gray value")
    func shapeMatchesCanvas() throws {
        let ctx = try makeContext()
        ctx.colorMode(.rgb, 1.0)
        ctx.fill(0.75)

        let s = ctx.createShape()
        s.beginShape()
        s.fill(0.75)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, ctx.canvas.fillColor, "shape vs canvas")
    }

    // MARK: α（#853 の「α をリテラル 1 で固定」）

    @Test("fill(gray, alpha) carries the alpha through")
    func fillWithAlpha() throws {
        let ctx = try makeContext()
        let s = ctx.createShape()
        s.beginShape()
        s.fill(128, 64)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, SIMD4(128 / 255, 128 / 255, 128 / 255, 64 / 255), "fill")
    }

    @Test("stroke(gray, alpha) carries the alpha through")
    func strokeWithAlpha() throws {
        let ctx = try makeContext()
        let s = ctx.createShape()
        s.beginShape()
        s.stroke(255, 0)
        s.endShape()

        expectClose(s.capturedStyle.strokeColor, SIMD4(1, 1, 1, 0), "stroke")
    }

    @Test("alpha follows its own colorMode range")
    func alphaFollowsItsOwnRange() throws {
        let ctx = try makeContext()
        ctx.colorMode(.rgb, 255, 255, 255, 1)
        let s = ctx.createShape()
        s.beginShape()
        s.fill(128, 0.5)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, SIMD4(128 / 255, 128 / 255, 128 / 255, 0.5), "fill")
    }

    // MARK: 境界値

    @Test("a shape built without a sketch context keeps the 0-255 default")
    func withoutContextUsesDefault() {
        // テストやライブラリ内部が直接組む MShape は colorMode を写す相手がいない。
        // 既定の ColorModeConfig（rgb 0-255）で解釈されること。
        let s = MShape(device: device, kind: .path2D)
        s.beginShape()
        s.fill(255)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, SIMD4(1, 1, 1, 1), "fill")
    }

    @Test("the color mode is the one in effect when the shape was created")
    func capturedAtCreationTime() throws {
        let ctx = try makeContext()
        ctx.colorMode(.rgb, 1.0)
        let s = ctx.createShape()

        // 作成後にスケッチ側を戻しても、このシェイプは作成時のレンジで解釈し続ける
        // （fill / stroke / material と同じ「createShape() 時点のスナップショット」）
        ctx.colorMode(.rgb, 255)
        s.beginShape()
        s.fill(0.5)
        s.endShape()

        expectClose(s.capturedStyle.fillColor, SIMD4(0.5, 0.5, 0.5, 1), "fill")
    }
}
