import metaphor
import MetaphorFPSLogger

@main
final class PluginFPSLoggerApp: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 640, height: 360,
            title: "Plugin: FPS Logger",
            plugins: [PluginFactory { FPSLoggerPlugin(interval: 60) }]
        )
    }

    func draw() {
        background(0)

        // Animate circles to generate some GPU load
        let t = Float(frameCount) * 0.02
        for i in 0..<50 {
            let fi = Float(i)
            let x = width / 2 + cos(t + fi * 0.5) * fi * 4
            let y = height / 2 + sin(t + fi * 0.7) * fi * 3
            fill(fi * 5, 100, 255 - fi * 5, 150)
            noStroke()
            circle(x, y, 20 + fi * 0.5)
        }
    }
}
