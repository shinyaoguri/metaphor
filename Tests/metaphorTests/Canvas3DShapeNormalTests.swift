import Metal
import Testing
import simd

@testable import MetaphorCore

// MARK: - イミディエイトな 3D シェイプの法線自動計算（#875）

/// `beginShape3D()` + `vertex(x, y, z)` で `normal()` を書かなかったシェイプへ入る
/// 面法線を固定する。
///
/// 旧実装（`autoComputeNormals()`）は **3 頂点ごと**（`i += 3`）に面法線を入れていた。
/// これは `.triangles` の topology にしか合っていないため、`.triangleStrip` /
/// `.triangleFan` では後ろの頂点が既定の (0, 1, 0) のまま取り残されていた。
/// リテインド側（#738）と同じ共有ヘルパー `FaceNormals` へ寄せて、規則を 1 つにする。
///
/// `endShape()` は `shapeVertices3D` を消さない（消すのは次の `beginShape()`）ので、
/// 描画後の頂点配列をそのまま読んで法線を確かめられる。エンコーダ無しの `Canvas3D`
/// では `drawShape3DVertices()` が早期 return するだけで、法線の書き込みはその手前で
/// 終わっている。
@Suite("Canvas3D Shape Auto Normals", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas3DShapeAutoNormalTests {

    private func makeCanvas() throws -> Canvas3D {
        try Canvas3D(renderer: try MetaphorRenderer(width: 64, height: 64))
    }

    /// 記録した頂点の法線（テッセレーション前の元頂点と同じ並び）。
    private func normals(_ canvas: Canvas3D) -> [SIMD3<Float>] {
        canvas.shapeVertices3D.map(\.normal)
    }

    /// z = 0 平面のジグザグ 5 頂点。旧実装だと後ろ 2 頂点が漏れる。
    private func zigzagStrip(_ canvas: Canvas3D) {
        canvas.beginShape(.triangleStrip)
        canvas.vertex(0, 0, 0)
        canvas.vertex(0, 1, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(1, 1, 0)
        canvas.vertex(2, 0, 0)
        canvas.endShape()
    }

    @Test("triangleStrip は全頂点に面法線が付く")
    func triangleStripCoversEveryVertex() throws {
        let canvas = try makeCanvas()
        zigzagStrip(canvas)

        let ns = normals(canvas)
        #expect(ns.count == 5)
        for (i, n) in ns.enumerated() {
            #expect(abs(abs(n.z) - 1) < 0.001,
                    "頂点 \(i) にも面法線が付く（既定の (0, 1, 0) が残っていない）: \(n) — #875")
        }
        // 巻き方向の反転はインデックスを組む側が補正済みなので、全体で向きが揃う。
        let first = ns[0]
        for (i, n) in ns.enumerated() {
            #expect(simd_dot(first, n) > 0.999, "頂点 \(i) の向きが先頭と揃う: \(n) — #875")
        }
    }

    @Test("triangleFan は全頂点に面法線が付く")
    func triangleFanCoversEveryVertex() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.triangleFan)
        canvas.vertex(0, 0, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(1, 1, 0)
        canvas.vertex(0, 1, 0)
        canvas.vertex(-1, 1, 0)
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 5)
        for (i, n) in ns.enumerated() {
            #expect(abs(abs(n.z) - 1) < 0.001,
                    "頂点 \(i) にも面法線が付く: \(n) — #875")
        }
    }

    // 回帰: `.triangles` は各頂点が 1 三角形にしか属さないので「3 頂点ごと」と同じ結果。
    // 移行で変わらないことを固定する。
    @Test("triangles の面法線は移行前と同じ")
    func trianglesUnchanged() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.triangles)
        canvas.vertex(0, 0, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(0, 1, 0)
        // 2 枚目は向きを裏返して置く（三角形ごとに別の法線が付くこと）
        canvas.vertex(0, 0, 1)
        canvas.vertex(0, 1, 1)
        canvas.vertex(1, 0, 1)
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 6)
        for i in 0..<3 {
            #expect(abs(ns[i].z - 1) < 0.001 && abs(ns[i].x) < 0.001 && abs(ns[i].y) < 0.001,
                    "1 枚目は +z: \(ns[i])")
        }
        for i in 3..<6 {
            #expect(abs(ns[i].z + 1) < 0.001 && abs(ns[i].x) < 0.001 && abs(ns[i].y) < 0.001,
                    "2 枚目は -z: \(ns[i])")
        }
    }

    // 回帰: 平面ポリゴンでは全三角形の面法線が一致するので、
    // 「先頭 3 頂点の面法線を全頂点へ」（旧実装）と同じ結果になる。
    @Test("平面な polygon の面法線は移行前と同じ")
    func planarPolygonUnchanged() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.polygon)
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            canvas.vertex(cos(a), sin(a), 0)
        }
        canvas.endShape(.close)

        let ns = normals(canvas)
        #expect(ns.count == 5)
        for (i, n) in ns.enumerated() {
            #expect(abs(n.z - 1) < 0.001 && abs(n.x) < 0.001 && abs(n.y) < 0.001,
                    "頂点 \(i) は +z の面法線: \(n)")
        }
    }

    // 非平面ポリゴンは「先頭 3 頂点の面法線を全頂点へ」から
    // 「面積重み付きの平均」へ変わる（絵が動く側）。
    @Test("非平面な polygon は面積重み付きの平均になる")
    func nonPlanarPolygonAverages() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.polygon)
        canvas.vertex(0, 0, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(1, 1, 0)
        canvas.vertex(0, 1, 1)   // z = 0 平面から外す
        canvas.endShape(.close)

        let ns = normals(canvas)
        #expect(ns.count == 4)
        // 頂点 1 は z = 0 平面の三角形にしか属さないので (0, 0, 1) のまま。
        #expect(abs(ns[1].z - 1) < 0.001, "頂点 1 は面 1 枚ぶんのまま: \(ns[1]) — #875")
        // 平面から外れた頂点 3 は傾いた三角形の法線を受けるので +z ではなくなる。
        #expect(abs(ns[3].x) > 0.1 && abs(ns[3].y) > 0.1,
                "頂点 3 は傾いた面法線になる（先頭 3 頂点の面法線ではない）: \(ns[3]) — #875")
        for (i, n) in ns.enumerated() {
            #expect(abs(simd_length(n) - 1) < 0.001, "頂点 \(i) は正規化済み: \(n)")
        }
    }

    // `.lines` / `.points` に面はない。旧実装は「3 頂点ごとの面法線」という
    // 幾何的に無意味な値を入れていた（しかも後ろの頂点は既定値のまま）。
    // 面のインデックス列が空なので、リテインド側と同じく既定値のままにする。
    @Test("lines は幾何的に無意味な面法線を入れない", arguments: [ShapeMode.lines, .points])
    func lineAndPointModesKeepDefaultNormal(mode: ShapeMode) throws {
        let canvas = try makeCanvas()
        canvas.beginShape(mode)
        canvas.vertex(0, 0, 0)
        canvas.vertex(0, 1, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(1, 1, 0)
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 4)
        for (i, n) in ns.enumerated() {
            #expect(abs(n.x) < 0.001 && abs(n.y - 1) < 0.001 && abs(n.z) < 0.001,
                    "\(mode) の頂点 \(i) は既定の (0, 1, 0) のまま: \(n) — #875")
        }
    }

    // 失敗系: `normal()` を書いたシェイプでは自動計算が働かない。
    @Test("normal() を明示したら自動計算は働かない")
    func explicitNormalWins() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.triangleStrip)
        canvas.normal(1, 0, 0)
        canvas.vertex(0, 0, 0)
        canvas.vertex(0, 1, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(1, 1, 0)
        canvas.vertex(2, 0, 0)
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 5)
        for (i, n) in ns.enumerated() {
            #expect(abs(n.x - 1) < 0.001 && abs(n.y) < 0.001 && abs(n.z) < 0.001,
                    "頂点 \(i) は明示した (1, 0, 0) のまま: \(n) — #875")
        }
    }

    // 境界値: 3 頂点が一直線に並ぶ退化三角形。外積が零ベクトルになるので、
    // そのまま正規化すると NaN が頂点バッファへ流れる。既定値へ落ちること。
    @Test("退化した三角形は NaN にならず既定の法線へ落ちる")
    func degenerateTriangleFallsBack() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.triangles)
        canvas.vertex(0, 0, 0)
        canvas.vertex(1, 0, 0)
        canvas.vertex(2, 0, 0)   // 一直線
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 3)
        for (i, n) in ns.enumerated() {
            #expect(!n.x.isNaN && !n.y.isNaN && !n.z.isNaN, "頂点 \(i) に NaN を書き込まない: \(n)")
            #expect(abs(n.x) < 0.001 && abs(n.y - 1) < 0.001 && abs(n.z) < 0.001,
                    "頂点 \(i) は既定の (0, 1, 0) へ落ちる: \(n)")
        }
    }

    // 境界値: 三角形に満たない頂点数。テッセレーションが走らないので既定値のまま
    // （旧実装も同じ。クラッシュしないことの確認）。
    @Test("三角形に満たないシェイプは既定の法線のまま")
    func tooFewVerticesKeepDefault() throws {
        let canvas = try makeCanvas()
        canvas.beginShape(.polygon)
        canvas.vertex(0, 0, 0)
        canvas.vertex(1, 0, 0)
        canvas.endShape()

        let ns = normals(canvas)
        #expect(ns.count == 2)
        for n in ns {
            #expect(abs(n.y - 1) < 0.001, "既定の (0, 1, 0) のまま: \(n)")
        }
    }
}
