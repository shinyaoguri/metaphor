import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

/// Issue #813 で足した 2D 形状の Processing 語彙 3 本
/// （``Canvas2D/quadraticVertex(_:_:_:_:)`` / ``Canvas2D/bezierDetail(_:)`` /
/// ``Canvas2D/shapeMode(_:)``）を実測で留める。
///
/// ## なぜこのテストがあるか
///
/// `bezierDetail` は「同じ 3 次ベジェが描き方で違う細かさになる」ずれを直すために入った
/// （`bezier()` が 24 固定、`beginShape()` + `bezierVertex()` が `curveDetail`）。
/// このずれは**エラーにも警告にもならず絵だけが黙って変わる**種類なので、
/// 「両方が同じ分割数に従う」ことを assert しておかないと、片方の経路だけ元に戻っても
/// 誰も気付かない。#586 の実測どおり GPU 出力はバイト単位で再現するが、
/// `Tests/metaphorTests/Golden/` のシーンは 1 つも曲線を描いていないので
/// ゴールデン画像はこの回帰を拾わない。
@Suite("2D shape vocabulary (#813)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ShapeVocabularyTests {

    /// `beginShape()` 〜 頂点記録までを行い、展開後の頂点列を返す。
    private func expand(_ canvas: Canvas2D, _ record: (Canvas2D) -> Void) -> [(x: Float, y: Float)]
    {
        canvas.beginShape()
        record(canvas)
        return canvas.expandShapeVerticesEx().map { (x: $0.x, y: $0.y) }
    }

    // MARK: - bezierDetail: 2 つの経路が同じ分割数に従う

    /// 守る行: `Canvas2DShapes.swift` の `let segments = bezierDetailCount`
    /// （#813 まで `24` のリテラルだった）。
    @Test("bezier() は bezierDetail() に従う（24 固定ではない）")
    func onePieceBezierFollowsBezierDetail() throws {
        let canvas = try MetalTestHelper.canvas2D()

        // bezier() は頂点列を残さず strokeLine を呼ぶだけなので、頂点カーソルの伸び方で測る。
        func strokedVertices(detail: Int) -> Int {
            canvas.bezierDetail(detail)
            canvas.vertexCount = 0
            canvas.bezier(60, 280, 140, 40, 340, 320, 420, 80)
            return canvas.vertexCount
        }

        let coarse = strokedVertices(detail: 4)
        let fine = strokedVertices(detail: 40)
        #expect(coarse > 0, "前提: bezier() が線分を積んでいる")
        // 分割数 10 倍なら積まれる線分もおよそ 10 倍になる（1 セグメント = 一定数の頂点）。
        #expect(fine == coarse * 10)
    }

    /// 守る行: `Canvas2DShapeBuilder.swift` の `case .bezier:` の `let segments = bezierDetailCount`
    /// （#813 まで `curveDetailCount` を読んでいた）。
    @Test("bezierVertex() は curveDetail ではなく bezierDetail に従う")
    func bezierVertexFollowsBezierDetail() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(6)
        canvas.curveDetail(31)  // 効いてはいけない側

        let verts = expand(canvas) {
            $0.vertex(80, 260)
            $0.bezierVertex(120, 60, 360, 60, 400, 260)
        }

        // 始点 1 + 分割数 6
        #expect(verts.count == 7)
    }

    /// #813 の本丸。同じ制御点なら、どちらの描き方でも同じ点列が出る。
    @Test("bezier() と bezierVertex() は同じ分割で同じ点を通る")
    func bothBezierPathsAgree() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(9)

        let verts = expand(canvas) {
            $0.vertex(80, 260)
            $0.bezierVertex(120, 60, 360, 60, 400, 260)
        }

        // bezier() が内部で刻む t と同じ刻みを、同じ制御点で再現する。
        let segments = 9
        #expect(verts.count == segments + 1)
        for step in 0...segments {
            let t = Float(step) / Float(segments)
            let ex = bezierPoint(80, 120, 360, 400, t)
            let ey = bezierPoint(260, 60, 60, 260, t)
            #expect(abs(verts[step].x - ex) < 0.001)
            #expect(abs(verts[step].y - ey) < 0.001)
        }
    }

    /// 既定値は `curveDetail` と揃えた 20（Processing / p5 も同じ）。
    /// ここが動くと `bezier()` / `bezierVertex()` の実行結果画像が黙って古くなる。
    @Test("bezierDetail の既定は curveDetail と同じ 20")
    func defaultDetailMatchesCurveDetail() throws {
        let canvas = try MetalTestHelper.canvas2D()
        #expect(canvas.bezierDetailCount == 20)
        #expect(canvas.bezierDetailCount == canvas.curveDetailCount)
    }

    // MARK: - bezierDetail: 境界値・失敗系

    @Test(
        "bezierDetail は 1 未満を 1 に切り上げる（0 除算・空の点列を作らない）",
        arguments: [0, -1, Int.min])
    func detailClampsBelowOne(_ n: Int) throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(n)
        #expect(canvas.bezierDetailCount == 1)

        // 1 セグメント = 始点と終点だけの直線に潰れる（クラッシュしない）。
        let verts = expand(canvas) {
            $0.vertex(0, 0)
            $0.bezierVertex(10, 90, 90, 90, 100, 0)
        }
        #expect(verts.count == 2)
        #expect(abs(verts[1].x - 100) < 0.001)
        #expect(abs(verts[1].y - 0) < 0.001)
    }

    // MARK: - quadraticVertex

    /// 2 次ベジェは `P0 + 2/3(Q-P0)` / `P2 + 2/3(Q-P2)` を制御点に持つ 3 次と等しい。
    /// 昇格の式が壊れると曲線が制御点へ寄りすぎる／離れすぎるが、絵は「それらしく」出るので、
    /// 解析解と突き合わせて留める。
    @Test("quadraticVertex は 2 次ベジェの解析解と一致する")
    func quadraticMatchesClosedForm() throws {
        let canvas = try MetalTestHelper.canvas2D()
        let segments = 12
        canvas.bezierDetail(segments)

        let p0 = (x: Float(40), y: Float(300))
        let q = (x: Float(220), y: Float(20))
        let p2 = (x: Float(400), y: Float(300))

        let verts = expand(canvas) {
            $0.vertex(p0.x, p0.y)
            $0.quadraticVertex(q.x, q.y, p2.x, p2.y)
        }

        #expect(verts.count == segments + 1)
        for step in 0...segments {
            let t = Float(step) / Float(segments)
            let u = 1 - t
            // 2 次ベジェの定義そのもの
            let ex = u * u * p0.x + 2 * u * t * q.x + t * t * p2.x
            let ey = u * u * p0.y + 2 * u * t * q.y + t * t * p2.y
            #expect(abs(verts[step].x - ex) < 0.01)
            #expect(abs(verts[step].y - ey) < 0.01)
        }
    }

    @Test("quadraticVertex は等価な bezierVertex と同じ点列になる")
    func quadraticEqualsPromotedCubic() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(7)

        let quad = expand(canvas) {
            $0.vertex(40, 300)
            $0.quadraticVertex(220, 20, 400, 300)
        }

        let k: Float = 2.0 / 3.0
        let cubic = expand(canvas) {
            $0.vertex(40, 300)
            $0.bezierVertex(
                40 + k * (220 - 40), 300 + k * (20 - 300),
                400 + k * (220 - 400), 300 + k * (20 - 300),
                400, 300)
        }

        #expect(quad.count == cubic.count)
        for (a, b) in zip(quad, cubic) {
            #expect(abs(a.x - b.x) < 0.001)
            #expect(abs(a.y - b.y) < 0.001)
        }
    }

    /// 失敗系: `beginShape()` の外は他の頂点 API と同じく黙って無視する。
    @Test("beginShape の外の quadraticVertex は無視される")
    func quadraticOutsideShapeIsIgnored() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.quadraticVertex(10, 10, 20, 20)
        #expect(canvas.shapeVertexList.isEmpty)
    }

    /// 境界値: 直前の頂点が無いときは原点を始点に採る
    /// （`expandShapeVerticesEx()` の `lastX` / `lastY` の初期値と揃える）。
    @Test("直前の頂点が無い quadraticVertex は原点から引く")
    func quadraticWithoutPrecedingVertexStartsAtOrigin() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(4)

        let verts = expand(canvas) {
            $0.quadraticVertex(100, 0, 200, 200)
        }

        // 展開は始点を書き出さないので、分割数ぶんだけ並ぶ。
        #expect(verts.count == 4)
        let last = try #require(verts.last)
        #expect(abs(last.x - 200) < 0.001)
        #expect(abs(last.y - 200) < 0.001)

        // t = 0.5 の点が、原点を始点にした 2 次ベジェの解析解と一致する。
        let mid = verts[1]
        #expect(abs(mid.x - (0.25 * 0 + 0.5 * 100 + 0.25 * 200)) < 0.01)
        #expect(abs(mid.y - (0.25 * 0 + 0.5 * 0 + 0.25 * 200)) < 0.01)
    }

    // MARK: - shapeMode

    /// `.corner` は恒等変換。ここが動くと既存スケッチの絵が黙って動く。
    @Test("shapeMode の既定 .corner は引数をそのまま使う")
    func cornerIsIdentity() throws {
        let r = SketchContext.resolveShapePosition(.corner, 30, 50, 120, 80)
        #expect(r.x == 30)
        #expect(r.y == 50)
        #expect(r.w == 120)
        #expect(r.h == 80)
    }

    /// `.corners` は w, h を右下隅の座標として読む（Processing の `PGraphics.shape()` と同じ）。
    @Test("shapeMode(.corners) は w, h を右下隅として読む")
    func cornersReadsLowerRight() throws {
        let r = SketchContext.resolveShapePosition(.corners, 30, 50, 150, 130)
        #expect(r.x == 30)
        #expect(r.y == 50)
        #expect(r.w == 120)
        #expect(r.h == 80)
    }

    /// `.center` は x, y を中心として読む。
    @Test("shapeMode(.center) は x, y を中心として読む")
    func centerReadsCenter() throws {
        let r = SketchContext.resolveShapePosition(.center, 90, 90, 120, 80)
        #expect(r.x == 30)
        #expect(r.y == 50)
        #expect(r.w == 120)
        #expect(r.h == 80)
    }

    /// 境界値: 右下隅が左上隅より手前だと負のサイズになる。
    /// Processing も clamp しないので、黙って符号を落とさないことだけ留める。
    @Test("shapeMode(.corners) で隅が逆転すると負のサイズになる")
    func cornersWithInvertedCornersGoesNegative() throws {
        let r = SketchContext.resolveShapePosition(.corners, 200, 200, 50, 60)
        #expect(r.w == -150)
        #expect(r.h == -140)
    }

    @Test("shapeMode() は Canvas2D の状態を切り替える")
    func setterStoresMode() throws {
        let canvas = try MetalTestHelper.canvas2D()
        #expect(canvas.currentShapePositionMode == .corner)
        canvas.shapeMode(.center)
        #expect(canvas.currentShapePositionMode == .center)
    }

    // MARK: - push/pop に乗ること

    /// `bezierDetail` / `shapeMode` は `rectMode` / `curveDetail` と同じスタイル状態なので、
    /// `push()` / `pop()` と `pushStyle()` / `popStyle()` の両方で戻る。
    @Test("bezierDetail と shapeMode は push/pop で戻る")
    func stateIsSavedByPushPop() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(33)
        canvas.shapeMode(.corners)

        canvas.push()
        canvas.bezierDetail(3)
        canvas.shapeMode(.center)
        canvas.pop()

        #expect(canvas.bezierDetailCount == 33)
        #expect(canvas.currentShapePositionMode == .corners)
    }

    @Test("bezierDetail と shapeMode は pushStyle/popStyle で戻る")
    func stateIsSavedByPushStylePopStyle() throws {
        let canvas = try MetalTestHelper.canvas2D()
        canvas.bezierDetail(33)
        canvas.shapeMode(.corners)

        canvas.pushStyle()
        canvas.bezierDetail(3)
        canvas.shapeMode(.center)
        canvas.popStyle()

        #expect(canvas.bezierDetailCount == 33)
        #expect(canvas.currentShapePositionMode == .corners)
    }
}
