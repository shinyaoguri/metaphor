import metaphor

@main
final class Map: Sketch {
    var config: SketchConfig { SketchConfig(title: "Map", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        background(0)
        let c = map(mouseX, 0, width, 0, 175)
        let d = map(mouseX, 0, width, 40, 300)
        fill(255, c, 0)
        ellipse(width / 2, height / 2, d, d)
    }
}
