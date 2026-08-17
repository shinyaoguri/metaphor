import metaphor

/// CubicGridRetained（未移植のスタブ）
///
/// `createShape` / `addChild` / `setFill` は **metaphor に実装済み**で、原典の
/// `createShape(GROUP)` + 箱ごとの `setFill()` はそのまま書ける。止まっているのは性能側:
/// 原典は 34,221 個（17 × 33 × 61）の箱を子シェイプとして持つが、metaphor の `.group`
/// は 1 本の VBO に畳まれず子を 1 つずつ描く（`MShapeDrawing.swift` の `case .group:`）。
/// 素直に書くと 34,221 ドローコールになり、「リテインドで大量ジオメトリを速く描く」という
/// 原典の題意が壊れる。1 メッシュへ畳めば 1 ドローコールで済むが、それには箱ごとに違う色
/// （原典は `color(abs(i), abs(j), abs(k), 50)`）を与える 3D 頂点カラーの公開 API が要る。
///
/// → #734 が入ったら実装に起こす。
///
/// 原典: CubicGridRetained.pde

@main
final class CubicGridRetained: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "CubicGridRetained (Stub)")
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
                + "Waiting on per-element color for a batched shape (#734).",
            width / 2, height / 2
        )
    }
}
