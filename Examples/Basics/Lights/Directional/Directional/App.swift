import metaphor

@main
final class Directional: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Directional") }
    func setup() { noStroke(); fill(204) }
    func draw() {
        background(0)
        let dirY = (mouseY / height - 0.5) * 2
        let dirX = (mouseX / width - 0.5) * 2
        directionalLight(-dirX, -dirY, -1, color: Color(gray: 204.0/255))
        translate(width / 2 - 100, height / 2, 0)
        sphere(80)
        translate(200, 0, 0)
        sphere(80)
    }
}
