import Metal
import Testing
import simd

@testable import MetaphorCore

// MARK: - normal() の持続範囲（#876）

/// `normal()` が何頂点に効くかを、リテインドとイミディエイトの**両方**で固定する。
///
/// リテインド（`MShapeBuilder`）は頂点を積むたびに `pendingNormal3D` を nil へ戻して
/// いたため **次の 1 頂点だけ**、イミディエイト（`Canvas3D`）は `endShape()` まで持続、
/// という非対称があった。doc も層ごとに食い違っていた（`Sketch+3D.swift`「以降の
/// 3D 頂点」 vs `MShapeBuilder.swift`「次の3D頂点」）。
///
/// Processing の `PShape.normal()` / `normal()` はどちらも「以降の頂点に持続」で、
/// 移植元の `.pde` も `normal()` を 1 回だけ呼んで全頂点に効かせている。
/// イミディエイト側（持続）へ揃える。
@Suite("normal() scope", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ShapeNormalScopeTests {

    private let device = MTLCreateSystemDefaultDevice()!

    private func makeShape() -> MShape {
        MShape(device: device, kind: .path2D)
    }

    private func makeCanvas() throws -> Canvas3D {
        try Canvas3D(renderer: try MetaphorRenderer(width: 64, height: 64))
    }

    /// 三角形 1 枚ぶんの頂点位置（z = 0 平面）。既定の (0, 1, 0) とも
    /// 面法線 (0, 0, ±1) とも違う値を `normal()` で入れて、持続範囲だけを見る。
    private static let triangle: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
    ]

    // MARK: - リテインド

    @Test("リテインドの normal() は endShape() まで持続する")
    func retainedNormalPersists() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)   // 1 回だけ
        for p in Self.triangle { s.vertex(p.x, p.y, p.z) }
        s.endShape()

        #expect(s.vertices3D.count == 3)
        for (i, v) in s.vertices3D.enumerated() {
            #expect(v.normal == SIMD3<Float>(1, 0, 0),
                    "頂点 \(i) にも (1, 0, 0) が効く: \(v.normal) — #876")
        }
    }

    @Test("途中で呼んだ normal() はそこから先の頂点に効く")
    func retainedNormalAppliesFromThereOn() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        s.vertex(0, 0, 0)
        s.vertex(1, 0, 0)
        s.normal(0, 0, 1)   // ここで差し替え
        s.vertex(0, 1, 0)
        s.vertex(1, 1, 0)
        s.endShape()

        let ns = s.vertices3D.map(\.normal)
        #expect(ns.count == 4)
        #expect(ns[0] == SIMD3<Float>(1, 0, 0))
        #expect(ns[1] == SIMD3<Float>(1, 0, 0), "差し替え前は前の値が続く: \(ns[1]) — #876")
        #expect(ns[2] == SIMD3<Float>(0, 0, 1))
        #expect(ns[3] == SIMD3<Float>(0, 0, 1), "差し替え後も持続する: \(ns[3]) — #876")
    }

    // 回帰: 頂点ごとに呼べば頂点ごとに変えられる（Trefoil のような滑らかな面）。
    // 持続へ揃えてもこの書き方の意味は変わらない。
    @Test("頂点ごとに normal() を呼べば頂点ごとに変わる")
    func retainedPerVertexNormalStillWorks() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        s.vertex(0, 0, 0)
        s.normal(0, 1, 0)
        s.vertex(1, 0, 0)
        s.normal(0, 0, 1)
        s.vertex(0, 1, 0)
        s.endShape()

        let ns = s.vertices3D.map(\.normal)
        #expect(ns == [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)])
    }

    // UV 付きの頂点も同じ経路（`vertex(x, y, z, u, v)` も nil へ戻していた）。
    @Test("UV 付きの頂点でも normal() は持続する")
    func retainedNormalPersistsForTexturedVertices() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        s.vertex(0, 0, 0, 0, 0)
        s.vertex(1, 0, 0, 1, 0)
        s.vertex(0, 1, 0, 0, 1)
        s.endShape()

        for (i, v) in s.vertices3D.enumerated() {
            #expect(v.normal == SIMD3<Float>(1, 0, 0), "頂点 \(i): \(v.normal) — #876")
        }
    }

    // 境界値: `beginShape()` が持ち越しを断つ。前のシェイプの normal() が
    // 次のシェイプへ漏れない（持続範囲は 1 シェイプの中だけ）。
    @Test("beginShape() は normal() の持ち越しを断つ")
    func beginShapeResetsPendingNormal() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        s.vertex(0, 0, 0)
        s.endShape()

        s.beginShape(.triangles)
        for p in Self.triangle { s.vertex(p.x, p.y, p.z) }
        s.endShape()

        // 2 回目は normal() 未指定なので面法線の自動計算に委ねられる（#738）。
        // 記録段階では既定値が入っている。
        #expect(s.usedExplicitNormal3D == false, "2 回目のシェイプは normal() 未使用 — #876")
        for (i, v) in s.vertices3D.enumerated() {
            #expect(v.normal == SIMD3<Float>(0, 1, 0),
                    "頂点 \(i) は前のシェイプの (1, 0, 0) を継がない: \(v.normal) — #876")
        }
    }

    // 失敗系: 最後の頂点より後に呼んだ normal() は誰にも効かない
    // （持続の対象は「以降の頂点」であって、遡って適用はしない）。
    @Test("最後の頂点より後の normal() は誰にも効かない")
    func normalAfterLastVertexAffectsNobody() {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        for p in Self.triangle { s.vertex(p.x, p.y, p.z) }
        s.normal(0, 0, 1)   // 頂点はもう積まれない
        s.endShape()

        for (i, v) in s.vertices3D.enumerated() {
            #expect(v.normal == SIMD3<Float>(1, 0, 0),
                    "頂点 \(i) は後から呼んだ (0, 0, 1) に書き換わらない: \(v.normal) — #876")
        }
    }

    // MARK: - 層をまたいだ対称性

    @Test("同じ書き方ならリテインドとイミディエイトが同じ法線になる")
    func retainedMatchesImmediate() throws {
        let s = makeShape()
        s.beginShape(.triangles)
        s.normal(1, 0, 0)
        for p in Self.triangle { s.vertex(p.x, p.y, p.z) }
        s.endShape()

        let canvas = try makeCanvas()
        canvas.beginShape(.triangles)
        canvas.normal(1, 0, 0)
        for p in Self.triangle { canvas.vertex(p.x, p.y, p.z) }
        canvas.endShape()

        let retained = s.vertices3D.map(\.normal)
        let immediate = canvas.shapeVertices3D.map(\.normal)
        #expect(retained == immediate,
                "retained=\(retained) immediate=\(immediate) — #876")
    }
}
