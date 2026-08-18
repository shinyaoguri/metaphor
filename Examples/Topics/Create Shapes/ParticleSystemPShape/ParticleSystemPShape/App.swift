import metaphor

/// ParticleSystemPShape（未移植のスタブ）
///
/// `createShape` / `addChild` / `texture` は **metaphor に実装済み**で、テクスチャ付き
/// クアッドのジオメトリはそのまま書ける。足りないのは**粒子ごとの α**
/// （原典は 10,000 個それぞれに `setTint(color(255, lifespan))`）:
///
/// - `MShape.setTint()` はどの描画経路でも効かない。値は記録されるだけ
///   （#852 で警告による明示化まで済み。効かせるか非推奨にするかは #905 で判断）
/// - 代わりに頂点カラーで持たせる道も、3D は色を与える公開 API が無く（#734）、
///   2D 描画経路は頂点カラー自体が未対応で警告して捨てる
/// - `.group` は 1 本の VBO に畳まれず子を 1 つずつ描く
///   （`MShapeDrawing.swift` の `case .group:`）。子ごとに `setFill()` で α を与えれば
///   絵は出せるが 10,000 ドローコールになり、「PShape で最適化する」題意が壊れる
///
/// → #734 / #905 が入ったら実装に起こす。
///
/// 原典: ParticleSystemPShape.pde
@main
final class ParticleSystemPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ParticleSystemPShape (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text(
            "createShape / addChild are implemented — no missing API here.\n"
                + "Waiting on per-particle alpha: setTint is ignored (#905)\n"
                + "and per-vertex color is unavailable (#734).",
            width / 2, height / 2
        )
    }
}
