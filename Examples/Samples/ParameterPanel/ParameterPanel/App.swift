import metaphor

/// Declare parameters with `@Param` and get a live control panel from a single
/// `gui.params()` call.
///
/// The panel and an AI agent are symmetric clients of the same store, so every
/// value here can also be changed from outside without rebuilding:
///
/// ```sh
/// cat .metaphor/params/params.json
/// echo '{"id":"set-1","values":{"count":24,"palette":"warm"}}' \
///   > .metaphor/params/set-request.json
/// ```
///
/// Whatever you drag (or write) is persisted to `.metaphor/params/params.json`
/// and restored on the next launch — `setup()` and `draw()` see the restored
/// values from the very first frame.
@main
final class ParameterPanelApp: Sketch {
    @Param(min: 3, max: 64) var count: Int = 12
    @Param(min: 20, max: 200) var radius: Float = 120
    @Param(min: 0, max: 4) var speed: Float = 1.0
    @Param(min: 2, max: 40) var dotSize: Float = 14
    @Param var showRing: Bool = true
    @Param var tint: Color = Color(r: 0.4, g: 0.8, b: 1.0, a: 1.0)
    @Param(choices: ["cool", "warm", "mono"]) var palette: String = "cool"

    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Parameter Panel")
    }

    func draw() {
        background(18)

        let t = Float(frameCount) * 0.01 * speed
        translate(width / 2, height / 2)

        if showRing {
            noFill()
            stroke(tint)
            strokeWeight(1)
            circle(0, 0, radius * 2)
        }

        noStroke()
        for i in 0..<count {
            let angle = Float(i) / Float(count) * TWO_PI + t
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            fill(dotColor(index: i))
            circle(x, y, dotSize)
        }

        resetMatrix()
        gui.params()   // one line: sliders, toggle, color picker and choice button
    }

    /// Mixes the tint with a palette-dependent hue shift.
    private func dotColor(index: Int) -> Color {
        let phase = Float(index) / Float(count)
        switch palette {
        case "warm":
            return Color(r: 1.0, g: 0.4 + phase * 0.4, b: 0.2, a: 1.0)
        case "mono":
            let v = 0.3 + phase * 0.7
            return Color(r: v, g: v, b: v, a: 1.0)
        default:
            return Color(
                r: tint.r * (0.4 + phase * 0.6),
                g: tint.g,
                b: tint.b,
                a: 1.0
            )
        }
    }
}
