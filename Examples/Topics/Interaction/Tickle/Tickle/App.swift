import metaphor

@main
final class Tickle: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Tickle")
    }

    let message = "tickle"
    var x: Float = 0
    var y: Float = 0
    let hr: Float = 60
    let vr: Float = 20

    func setup() {
        textAlign(.center, .center)
        textSize(36)
        noStroke()
        x = width / 2
        y = height / 2
    }

    func draw() {
        fill(204, 120)
        rect(0, 0, width, height)
        if abs(mouseX - x) < hr && abs(mouseY - y) < vr {
            x += random(-5, 5)
            y += random(-5, 5)
        }
        fill(0)
        text(message, x, y)
    }
}
