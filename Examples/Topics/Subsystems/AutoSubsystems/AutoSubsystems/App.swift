import metaphor

/// `AutoSubsystemManager` でサブシステムの毎フレーム更新を自動化するサンプル。
///
/// 通常は `draw()` の中で `physics.step(deltaTime)` を手動で呼びますが、physics を
/// `SketchSubsystem` として `AutoSubsystemManager` に登録すると、フレーム前フックで
/// 自動的に `step()` が駆動されます。`draw()` は描画だけに集中できます。
///
/// （従来どおり手動で `physics.step()` を呼ぶ書き方もそのまま使えます。これは追加の
/// オプトイン機能です。）
@main
final class AutoSubsystemsApp: Sketch {
    let physics = Physics2D(cellSize: 50)

    var config: SketchConfig {
        SketchConfig(
            width: 640, height: 360,
            title: "Auto Subsystems Demo",
            // physics を登録するだけで、毎フレームの step() が自動化される。
            plugins: [PluginFactory { [physics] in AutoSubsystemManager([physics]) }]
        )
    }

    func setup() {
        physics.setGravity(0, 300)
        physics.bounds = (min: SIMD2(0, 0), max: SIMD2(width, height))
        for i in 0..<24 {
            let x = 40 + Float(i % 8) * 70
            let y = 40 + Float(i / 8) * 40
            _ = physics.addCircle(x: x, y: y, radius: 12, mass: 1)
        }
    }

    func draw() {
        // physics.step() はここでは呼ばない — AutoSubsystemManager が自動で進める。
        background(18)
        noStroke()
        fill(120, 200, 255)
        for body in physics.bodies {
            circle(body.position.x, body.position.y, 24)
        }
    }
}
