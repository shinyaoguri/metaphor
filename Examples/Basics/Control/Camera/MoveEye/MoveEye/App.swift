import metaphor

@main
final class MoveEye: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Move Eye") }
    func setup() { fill(204) }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(0, 0, -1, color: Color(gray: 128.0/255))
        background(0)
        camera(eye: SIMD3(30, mouseY, 220), center: SIMD3(0, 0, 0))
        noStroke()
        box(90)
        stroke(255)
        beginShape3D(.lines)
        vertex(-100, 0, 0); vertex(100, 0, 0)
        vertex(0, -100, 0); vertex(0, 100, 0)
        vertex(0, 0, -100); vertex(0, 0, 100)
        endShape3D()
    }
}
