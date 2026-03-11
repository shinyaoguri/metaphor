import metaphor
import MetaphorMouseTrail

@main
final class PluginMouseTrailApp: Sketch {
    let trail = MouseTrailPlugin(maxPoints: 100)

    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Plugin: Mouse Trail")
    }

    func setup() {
        trail.color = (r: 100, g: 200, b: 255)
        trail.maxRadius = 25
        registerPlugin(trail)
    }

    func draw() {
        background(20)

        // Draw the mouse trail from the plugin
        trail.drawTrail(self)

        // Crosshair at current mouse position
        stroke(255, 80)
        noFill()
        line(mouseX - 10, mouseY, mouseX + 10, mouseY)
        line(mouseX, mouseY - 10, mouseX, mouseY + 10)
    }
}
