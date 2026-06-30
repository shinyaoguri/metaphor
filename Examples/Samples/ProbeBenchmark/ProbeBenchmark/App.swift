import metaphor

/// AI協調ループの「往復時間」測定（Epic #75 実測フェーズ / #116）用の代表ワークロード。
///
/// 観測→編集→再観測ループの計測ハーネス（metaphor-cli#44）が、下の
/// **EDIT-TOKEN** 行を書き換えて「保存→反映」を観測できるよう設計してある。
/// トークンは見た目が明確に変わる定数（色・個数）に限定し、書き換え後の
/// フレームを `frame.json` の `stats`（平均色・コンテンツ占有率）で差分判定できる。
///
/// 2D（HUD オーバーレイ）と 3D（影オンのボックス列＋床＋球）を中規模に混在させ、
/// #70/#71 で導入した「記録→shadow→再生」の決定論パスも測定対象に含める。
///
/// ```sh
/// # 観測
/// echo '{"id":"snap-1"}' > .metaphor/probe/request.json
/// ```
@main
final class ProbeBenchmark: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 800, height: 600,
            title: "Probe Benchmark",
            plugins: [PluginFactory { MetaphorProbePlugin() }]
        )
    }

    // === EDIT-TOKENS（測定ハーネスがこの2行を書き換えて「反映」を観測する）===
    let benchColor = Color(r: 0.90, g: 0.30, b: 0.45)   // EDIT-TOKEN:color
    let boxCount = 5                                     // EDIT-TOKEN:count

    func setup() {
        // 影オン経路（記録→shadow→再生）を測定に乗せる。
        enableShadows()
    }

    func draw() {
        background(18)

        let t = Float(frameCount) * 0.02

        // --- 3D: ライト + 床 + 回転するボックス列 + 球 ---
        // カメラ方向（-z）寄りに当てて前面を照らし、強めの環境光で
        // benchColor が確実に画面に現れるようにする（編集が stats に効く）。
        directionalLight(-0.3, -0.5, -1, color: Color(gray: 1.0))
        ambientLight(0.6)

        // 床（影の落ち先）
        pushMatrix()
        translate(width / 2, height / 2 + 140, 0)
        noStroke()
        fill(60)
        box(520, 12, 520)
        popMatrix()

        // ボックス列（boxCount は EDIT-TOKEN）
        for i in 0..<boxCount {
            let frac = boxCount > 1 ? Float(i) / Float(boxCount - 1) : 0.5
            let x = width / 2 + (frac - 0.5) * 360
            pushMatrix()
            translate(x, height / 2, 0)
            rotateY(t + frac * 3)
            rotateX(t * 0.6)
            fill(benchColor)           // benchColor は EDIT-TOKEN
            box(56)
            popMatrix()
        }

        // 球
        pushMatrix()
        translate(width / 2, height / 2 - 90, 0)
        fill(120, 180, 240)
        sphere(40)
        popMatrix()

        // --- 2D オーバーレイ: HUD（3D の前面に重なる支配的パターン）---
        fill(255)
        textSize(16)
        text("frame \(frameCount)", 16, 28)
        noStroke()
        fill(benchColor)
        circle(width - 40, 40, 36)
        fill(255, 255, 255, 60)
        rect(16, height - 40, 200, 8)

        // --- 内部状態（frame.json の custom に出る）---
        probe("bench.frame", frameCount)
        probe("bench.boxCount", boxCount)
        probe("bench.t", t)
    }
}
