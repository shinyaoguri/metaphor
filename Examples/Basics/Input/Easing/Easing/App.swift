import metaphor

@main
final class Easing: Sketch {
    var x: Float = 0
    var y: Float = 0
    let easing: Float = 0.05
    var config: SketchConfig { SketchConfig(title: "Easing", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        background(51)
        let dx = mouseX - x
        x += dx * easing
        let dy = mouseY - y
        y += dy * easing
        ellipse(x, y, 66, 66)
    }
}
