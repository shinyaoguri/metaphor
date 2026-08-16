import Foundation
import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// 寸法として渡すと「落ちないまま黙って壊れる」値。
///
/// `@Test(arguments:)` は Suite の外（nonisolated）から評価されるため、`@MainActor` な
/// Suite の static プロパティには置けない。
private let nonFiniteDimensions: [Float] = [.nan, .signalingNaN, .infinity, -.infinity]

/// 有限だが退化している寸法。これらは**通す**（潰れたメッシュ・鏡像として意味がある）。
private let finiteDegenerateDimensions: [Float] = [0, -1, -1e30, 1e30]

/// プリミティブの寸法に非有限値（`NaN` / `±infinity`）を渡したときの契約を固定する（Issue #894）。
///
/// プリミティブの頂点数は寸法に依らないため（box は 24、plane は 4、それ以外は分割数だけで
/// 決まる）、`NaN` を渡してもバッファ長は変わらず**落ちません**。代わりに全頂点が非有限の
/// メッシュが黙って出来上がり、描いても何も出ないまま `Canvas3D` のメッシュキャッシュへ
/// `"mesh_box_nan_nan_nan"` というキーで載って居座っていました。
///
/// 分割数（#445）は下限へ丸めますが、寸法は丸めずに弾きます。分割数には「閉じた輪を作れる
/// 最小値 = 3」という明らかに正しい代わりの値がある一方、`NaN` の長さに相当する値は無く、
/// 勝手に 1 などへ丸めるとスケッチが頼んでいないジオメトリを黙って作ることになるためです。
@Suite("プリミティブ寸法の非有限ガード", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MeshNonFiniteDimensionTests {

    private static let size = 64

    private func makeCanvas3D() throws -> Canvas3D {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
        return try Canvas3D(renderer: renderer)
    }

    /// 位置に inf / NaN を含む頂点の個数を数えます。
    private func nonFinitePositionCount(of mesh: Mesh) -> Int {
        let vertices = mesh.vertexBuffer.contents()
            .bindMemory(to: Vertex3D.self, capacity: mesh.vertexCount)
        var count = 0
        for i in 0..<mesh.vertexCount {
            let p = vertices[i].position
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { count += 1 }
        }
        return count
    }

    // MARK: - Mesh ファクトリ直呼び

    @Test("Mesh ファクトリは非有限な寸法を throw で弾く", arguments: nonFiniteDimensions)
    func meshFactoriesRejectNonFiniteDimensions(bad: Float) throws {
        let device = try #require(MetalTestHelper.device)

        // 引数ごとに 1 つだけ壊す（他は正当な値）。どの口からでも弾かれることを見る
        #expect(throws: MetaphorError.self) { try Mesh.box(device: device, width: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.box(device: device, height: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.box(device: device, depth: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.sphere(device: device, radius: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.plane(device: device, width: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.plane(device: device, height: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.cylinder(device: device, radius: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.cylinder(device: device, height: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.cone(device: device, radius: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.cone(device: device, height: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.torus(device: device, ringRadius: bad) }
        #expect(throws: MetaphorError.self) { try Mesh.torus(device: device, tubeRadius: bad) }
    }

    // MARK: - 生成 API（キャッシュを汚さないこと）

    @Test("非有限な寸法の createXxxMesh は nil を返し、キャッシュへ載らない",
          arguments: nonFiniteDimensions)
    func createMeshRejectsNonFiniteAndKeepsCacheClean(bad: Float) throws {
        let canvas3D = try makeCanvas3D()
        let before = canvas3D.meshCacheCountForTesting

        #expect(canvas3D.createBoxMesh(bad, bad, bad) == nil)
        #expect(canvas3D.createBoxMesh(bad) == nil)
        #expect(canvas3D.createSphereMesh(bad) == nil)
        #expect(canvas3D.createPlaneMesh(bad, 1) == nil)
        #expect(canvas3D.createCylinderMesh(radius: bad, height: 1) == nil)
        #expect(canvas3D.createConeMesh(radius: 1, height: bad) == nil)
        #expect(canvas3D.createTorusMesh(ringRadius: bad, tubeRadius: 0.2) == nil)

        #expect(canvas3D.meshCacheCountForTesting == before,
                "非有限な寸法でキャッシュが増えた（\(canvas3D.meshCacheCountForTesting) != \(before)）")
        #expect(canvas3D.meshCache.keys.allSatisfy { !$0.contains("nan") && !$0.contains("inf") },
                "非有限値がキーに載っている: \(Array(canvas3D.meshCache.keys))")
    }

    /// 描画側で唯一寸法をキーに載せている `torus(ringRadius:tubeRadius:detail:)` も汚さない。
    @Test("非有限な寸法の torus() もキャッシュへ載らない")
    func drawingTorusKeepsCacheClean() throws {
        let canvas3D = try makeCanvas3D()
        let before = canvas3D.meshCacheCountForTesting

        canvas3D.torus(ringRadius: .nan, tubeRadius: 0.2)
        canvas3D.torus(ringRadius: 1, tubeRadius: .infinity)

        #expect(canvas3D.meshCacheCountForTesting == before)
        #expect(canvas3D.meshCache["torus_nan_0.2_24_12"] == nil)
    }

    // MARK: - ガードが効きすぎていないこと

    @Test("有限なら 0 も負も巨大値もそのまま通る", arguments: finiteDegenerateDimensions)
    func finiteDimensionsStillPass(value: Float) throws {
        let device = try #require(MetalTestHelper.device)
        let canvas3D = try makeCanvas3D()

        let box = try Mesh.box(device: device, width: value, height: value, depth: value)
        #expect(box.vertexCount == 24)
        #expect(nonFinitePositionCount(of: box) == 0,
                "有限な寸法から非有限な座標が出ている（width = \(value)）")

        #expect(try Mesh.plane(device: device, width: value, height: value).vertexCount == 4)
        #expect(canvas3D.createBoxMesh(value, value, value) != nil)
        #expect(canvas3D.createPlaneMesh(value, value) != nil)
        #expect(canvas3D.createSphereMesh(value) != nil)
    }

    @Test("正当な寸法はこれまでどおりキャッシュへ載り、同じ引数なら同一インスタンス")
    func validDimensionsStillCache() throws {
        let canvas3D = try makeCanvas3D()

        let first = try #require(canvas3D.createBoxMesh(2, 3, 4))
        #expect(canvas3D.meshCache["mesh_box_2.0_3.0_4.0"] != nil)

        let second = try #require(canvas3D.createBoxMesh(2, 3, 4))
        #expect(first === second, "同じ引数の再呼び出しで同一インスタンスが返らない")
    }
}
