import metaphor

/// Demonstrates automated per-frame subsystem updates using `AutoSubsystemManager`.
///
/// Normally you call `physics.step(deltaTime)` manually inside `draw()`. When you register
/// physics as a `SketchSubsystem` with `AutoSubsystemManager`, the pre-frame hook automatically
/// drives `step()`, freeing `draw()` to focus on rendering only.
///
/// (The traditional manual `physics.step()` approach still works. This is an opt-in feature.)
@main
final class AutoSubsystemsApp: Sketch {
    let physics = Physics2D(cellSize: 50)

    var config: SketchConfig {
        SketchConfig(
            width: 640, height: 360,
            title: "Auto Subsystems Demo",
            // Register physics to automate per-frame step() calls.
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
        // Do not call physics.step() here — AutoSubsystemManager advances it automatically.
        background(18)
        noStroke()
        fill(120, 200, 255)
        for body in physics.bodies {
            circle(body.position.x, body.position.y, 24)
        }
    }
}
