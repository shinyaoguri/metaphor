import metaphor

@main
final class Spot: Sketch {
    var config: SketchConfig { SketchConfig(title: "Spot", width: 640, height: 360) }
    func setup() { noStroke(); fill(204) }
    func draw() {
        background(0)
        directionalLight(51, 102, 126, 0, -1, 0)
        spotLight(204, 153, 0, 360, 160, 600, 0, 0, -1, Float.pi / 2, 600)
        spotLight(102, 153, 204, 360, mouseY, 600, 0, 0, -1, Float.pi / 2, 600)
        translate3D(width / 2, height / 2, 0)
        sphere(120)
    }
}
