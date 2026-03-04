import metaphor

@main
final class Spot: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Spot") }
    func setup() { noStroke(); fill(204) }
    func draw() {
        background(0)
        directionalLight(0, -1, 0, color: Color(r: 51.0/255, g: 102.0/255, b: 126.0/255))
        spotLight(360, 160, 600, 0, 0, -1, angle: Float.pi / 2, color: Color(r: 204.0/255, g: 153.0/255, b: 0))
        spotLight(360, mouseY, 600, 0, 0, -1, angle: Float.pi / 2, color: Color(r: 102.0/255, g: 153.0/255, b: 204.0/255))
        translate(width / 2, height / 2, 0)
        sphere(120)
    }
}
