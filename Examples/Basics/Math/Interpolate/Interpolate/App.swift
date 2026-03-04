import metaphor

@main
final class Interpolate: Sketch {
    var x: Float = 0; var y: Float = 0
    var config: SketchConfig { SketchConfig(title: "Interpolate", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        background(51)
        x = lerp(x, mouseX, 0.05)
        y = lerp(y, mouseY, 0.05)
        fill(255); stroke(255)
        ellipse(x, y, 66, 66)
    }
}
