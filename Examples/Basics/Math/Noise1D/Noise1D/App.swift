import metaphor

@main
final class Noise1D: Sketch {
    var xoff: Float = 0
    let xincrement: Float = 0.01
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise 1D") }
    func setup() { background(0); noStroke() }
    func draw() {
        fill(0, 10); rect(0, 0, width, height)
        let n = noise(xoff) * width
        xoff += xincrement
        fill(200)
        ellipse(n, height / 2, 64, 64)
    }
}
