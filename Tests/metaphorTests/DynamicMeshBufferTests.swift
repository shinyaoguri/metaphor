import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// `DynamicMesh` の GPU バッファ更新戦略を固定する（Issue #686）。
///
/// 以前は「どれか 1 つでも変わったら 3 種類すべてを `makeBuffer(bytes:)` で確保し直す」
/// 作りだった。頂点を動かすアニメーションでは毎フレーム走るため、リファレンス作品
/// #414 の地形（128×128 = 16,384 頂点 / 96,774 インデックス）で約 1MB/フレーム
/// ＝ 60fps で 60MB/s の確保になっていた。しかも **インデックスは一度も変わらない**。
@Suite("DynamicMesh buffers", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct DynamicMeshBufferTests {

    /// 三角形 1 枚（頂点 3 / インデックス 3）。
    private func makeTriangle(_ device: MTLDevice) -> DynamicMesh {
        let mesh = DynamicMesh(device: device)
        mesh.addNormal(SIMD3(0, 0, 1))
        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0.5, 1, 0)
        mesh.addTriangle(0, 1, 2)
        return mesh
    }

    /// 頂点バッファの中身（`Vertex3D` の position だけ）を読み戻します。
    private func positions(_ mesh: DynamicMesh) -> [SIMD3<Float>] {
        guard let buffer = mesh.vertexBuffer else { return [] }
        let pointer = buffer.contents().bindMemory(
            to: Vertex3D.self, capacity: mesh.vertexCount
        )
        return (0..<mesh.vertexCount).map { pointer[$0].position }
    }

    // MARK: - インデックスは巻き添えにしない

    @Test("頂点を書き換えてもインデックスバッファは作り直されない")
    func indexBufferSurvivesVertexUpdates() throws {
        let device = MetalTestHelper.device!
        let mesh = makeTriangle(device)
        mesh.ensureBuffers()
        let firstIndexBuffer = try #require(mesh.indexBuffer)

        for frame in 1...10 {
            mesh.setVertex(0, SIMD3(Float(frame) * 0.1, 0, 0))
            mesh.ensureBuffers()
        }

        // 同一オブジェクトのままであること（確保が走っていない）。
        #expect(mesh.indexBuffer === firstIndexBuffer)
    }

    @Test("インデックスを足したときはインデックスバッファが更新される")
    func indexBufferUpdatesWhenIndicesChange() throws {
        let device = MetalTestHelper.device!
        let mesh = makeTriangle(device)
        mesh.ensureBuffers()
        #expect(mesh.indexCount == 3)

        mesh.addVertex(1.5, 1, 0)
        mesh.addTriangle(1, 2, 3)
        mesh.ensureBuffers()

        #expect(mesh.indexCount == 6)
        let buffer = try #require(mesh.indexBuffer)
        let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: 6)
        #expect(Array(UnsafeBufferPointer(start: pointer, count: 6)) == [0, 1, 2, 1, 2, 3])
    }

    // MARK: - 頂点は使い回す

    @Test("頂点バッファは高々 3 枚を巡回する（確保し直さない）")
    func vertexBuffersCycleThroughRing() throws {
        let device = MetalTestHelper.device!
        let mesh = makeTriangle(device)

        var seen: [ObjectIdentifier] = []
        for frame in 0..<12 {
            mesh.setVertex(0, SIMD3(Float(frame), 0, 0))
            mesh.ensureBuffers()
            let buffer = try #require(mesh.vertexBuffer)
            let id = ObjectIdentifier(buffer)
            if !seen.contains(id) { seen.append(id) }
        }

        // トリプルバッファリングと同じ深さ。12 フレーム回しても 3 枚で足りる。
        #expect(seen.count <= 3)
    }

    @Test("使い回したバッファの中身は毎回そのフレームの頂点になる")
    func reusedBufferHoldsCurrentVertices() throws {
        let device = MetalTestHelper.device!
        let mesh = makeTriangle(device)

        for frame in 0..<8 {
            let y = Float(frame) * 0.25
            mesh.setVertex(2, SIMD3(0.5, y, 0))
            mesh.ensureBuffers()
            #expect(positions(mesh)[2] == SIMD3(0.5, y, 0))
        }
    }

    @Test("頂点が増えて容量を超えたら確保し直して全頂点が載る")
    func growingBeyondCapacityReallocates() throws {
        let device = MetalTestHelper.device!
        let mesh = DynamicMesh(device: device)
        mesh.addVertex(0, 0, 0)
        mesh.ensureBuffers()

        for i in 1...200 {
            mesh.addVertex(Float(i), 0, 0)
        }
        mesh.ensureBuffers()

        #expect(mesh.vertexCount == 201)
        let read = positions(mesh)
        #expect(read.count == 201)
        #expect(read[200] == SIMD3(200, 0, 0))
    }

    // MARK: - clear

    @Test("clear() でバッファを手放し、再構築できる")
    func clearReleasesAndRebuilds() throws {
        let device = MetalTestHelper.device!
        let mesh = makeTriangle(device)
        mesh.ensureBuffers()
        #expect(mesh.vertexBuffer != nil)

        mesh.clear()
        mesh.ensureBuffers()
        #expect(mesh.vertexBuffer == nil)
        #expect(mesh.indexBuffer == nil)

        mesh.addVertex(0, 0, 0)
        mesh.addVertex(1, 0, 0)
        mesh.addVertex(0.5, 1, 0)
        mesh.addTriangle(0, 1, 2)
        mesh.ensureBuffers()
        #expect(mesh.vertexBuffer != nil)
        #expect(mesh.indexBuffer != nil)
        #expect(positions(mesh)[1] == SIMD3(1, 0, 0))
    }

    // MARK: - UV

    @Test("UV を宣言したメッシュは頂点の移動で UV 付き頂点列も追随する")
    func uvVerticesFollowVertexMoves() throws {
        let device = MetalTestHelper.device!
        let mesh = DynamicMesh(device: device)
        mesh.addNormal(SIMD3(0, 0, 1))
        for (index, uv) in [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)].enumerated() {
            mesh.addTexCoord(uv)
            mesh.addVertex(Float(index), 0, 0)
        }
        mesh.addTriangle(0, 1, 2)
        mesh.ensureBuffers()

        mesh.setVertex(1, SIMD3(9, 9, 0))
        mesh.ensureBuffers()

        let buffer = try #require(mesh.uvVertexBuffer)
        let pointer = buffer.contents().bindMemory(to: Vertex3DTextured.self, capacity: 3)
        #expect(pointer[1].position == SIMD3(9, 9, 0))
        #expect(pointer[1].uv == SIMD2(1, 0))
    }
}
