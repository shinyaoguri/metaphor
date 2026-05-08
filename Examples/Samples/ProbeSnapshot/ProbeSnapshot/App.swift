import metaphor

/// MetaphorProbe を使って AI エージェントに「いま何が見えているか」と
/// 「内部状態」の両方を渡すサンプル。
///
/// 実行後、別ターミナルから次のようにリクエストファイルを書くと
/// `.metaphor/probe/current/frame.png` と `frame.json` が出力される。
///
/// ```sh
/// echo '{"id":"snap-1","label":"baseline"}' > .metaphor/probe/request.json
/// ```
///
/// id を変えて書き直すたびに、その瞬間のフレームと状態が AI に届く形で書き出される。
@main
final class ProbeSnapshotApp: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 640, height: 360,
            title: "Probe Snapshot Demo",
            plugins: [PluginFactory { MetaphorProbePlugin() }]
        )
    }

    func draw() {
        background(20)

        let t = Float(frameCount) * 0.02
        let cx = width / 2 + cos(t) * 80
        let cy = height / 2 + sin(t * 1.3) * 60
        let radius: Float = 40 + sin(t * 2) * 10

        noStroke()
        fill(220, 100, 140)
        circle(cx, cy, radius * 2)

        // AI が後で frame.json で読める値を申告。
        // プラグイン未登録時は完全な no-op。
        probe("circle.x", cx)
        probe("circle.y", cy)
        probe("circle.radius", radius)
        probe("phase", "orbiting")
    }
}
