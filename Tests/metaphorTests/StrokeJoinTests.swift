import MetaphorTestSupport
import Testing

@testable import MetaphorCore

// MARK: - strokeJoin(.round) の弧が外側を向く（#769）

/// `strokeJoin(.round)` は角の**外側**を半径 `strokeWeight / 2` の弧で埋める。
///
/// `Canvas2DVertexWriter.strokePolyline` の round 分岐は、外側オフセット方向どうしの
/// なす角（`|sweep| <= π`）を扇形で塗る。ここを長いほうの弧（`|sweep| > π`）に
/// 直してしまうと、塗られるのは 2 本のクアッドが既に覆っている**内側**だけになり、
/// 外側が空いて V 字の窪みとして残る（#769）。絵に出るのは外側だけなので、
/// 「外向き二等分線の上」を 1 画素読めばこの取り違えを直接捕まえられる。
///
/// 検査に使う Λ 字（96x96、`strokeWeight` 20 = `hw` 10）:
///
/// ```
///        (48, 30)      ← 頂点。外向き二等分線は真上 (0, -1)
///        /      \
///  (38, 84)    (58, 84)
/// ```
///
/// 頂点の真上は 2 本のクアッドの範囲外（どちらのクアッドも頂点で終端する）なので、
/// そこを塗れるのはジョインだけ。各モードが塗る距離は
/// - `.round`: 弧の半径まで = `hw`（10）
/// - `.bevel`: 外側オフセット 2 点を結ぶ弦まで = `hw * cos(sweep / 2)`（約 1.8）
///
/// なので、頂点から 7 px の点は「round なら塗られ、bevel なら塗られない」土地になる。
@Suite("strokeJoin(.round)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct StrokeJoinRoundTests {

    private static let size = 96
    /// Λ 字の頂点。
    private static let apex: (x: Int, y: Int) = (48, 30)
    private static let strokeWeight: Float = 20

    /// 指定したジョインで Λ 字を 1 本描く。
    private func chevron(_ join: StrokeJoin) throws -> GoldenImage {
        try OffscreenSketchHarness.render(size: Self.size) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noFill()
            ctx.stroke(Color(r: 1, g: 1, b: 1))
            ctx.strokeWeight(Self.strokeWeight)
            ctx.strokeJoin(join)
            ctx.beginShape()
            ctx.vertex(38, 84)
            ctx.vertex(Float(Self.apex.x), Float(Self.apex.y))
            ctx.vertex(58, 84)
            ctx.endShape()
        }
    }

    /// 頂点から外向き二等分線（真上）へ `distance` px 離れた画素の輝度。
    private func outward(_ fb: GoldenImage, distance: Int) -> Int {
        let i = ((Self.apex.y - distance) * fb.width + Self.apex.x) * 4
        return Int(fb.rgba[i])
    }

    @Test("角の外側が弧で塗られる")
    func fillsTheOuterWedge() throws {
        let fb = try chevron(.round)
        #expect(outward(fb, distance: 7) > 200,
                """
                頂点の外側 7 px（弧の半径 10 px の内側）が塗られていない。
                内側の弧を塗ってしまうと外側が V 字に欠ける — #769
                """)
    }

    @Test("弧は半径 strokeWeight / 2 を超えて広がらない")
    func doesNotSpillPastTheRadius() throws {
        let fb = try chevron(.round)
        #expect(outward(fb, distance: 18) < 40,
                "頂点の外側 18 px は弧の半径 10 px の外なので背景のままであるべき")
    }

    /// `.bevel` は同じ土地を弦で切り落とす。`.round` の検査点が
    /// 「ジョインの塗り方でしか変わらない場所」であることの裏取りでもある。
    @Test("bevel は同じ点を塗らない（round との対比）")
    func bevelCutsTheCorner() throws {
        let fb = try chevron(.bevel)
        #expect(outward(fb, distance: 7) < 40,
                "bevel は外側オフセット 2 点を結ぶ弦で切り落とすので、7 px 先は背景")
    }
}
