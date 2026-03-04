import metaphor

@main
final class MoveEye: Sketch {
    var config: SketchConfig { SketchConfig(title: "Move Eye", width: 640, height: 360) }
    func setup() { fill(204) }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(128, 128, 128, 0, 0, -1)
        background(0)
        camera(30, mouseY, 220, 0, 0, 0, 0, 1, 0)
        noStroke()
        box(90)
        stroke(255)
        line(-100, 0, 0, 100, 0, 0)
        line(0, -100, 0, 0, 100, 0)
        line(0, 0, -100, 0, 0, 100)
    }
}
