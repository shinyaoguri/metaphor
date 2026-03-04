import metaphor

@main
final class Directional: Sketch {
    var config: SketchConfig { SketchConfig(title: "Directional", width: 640, height: 360) }
    func setup() { noStroke(); fill(204) }
    func draw() {
        background(0)
        let dirY = (mouseY / height - 0.5) * 2
        let dirX = (mouseX / width - 0.5) * 2
        directionalLight(204, 204, 204, -dirX, -dirY, -1)
        translate3D(width / 2 - 100, height / 2, 0)
        sphere(80)
        translate3D(200, 0, 0)
        sphere(80)
    }
}
