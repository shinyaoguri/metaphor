import metaphor

@main
final class Orthographic: Sketch {
    var showPerspective = false
    var config: SketchConfig { SketchConfig(width: 600, height: 360, title: "Orthographic") }
    func setup() { noStroke(); fill(255) }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(0, 0, -1, color: Color(gray: 128.0/255))
        background(0)
        let far = map(mouseX, 0, width, 120, 400)
        if showPerspective {
            perspective(fov: Float.pi / 3, near: 10, far: far)
        } else {
            ortho(left: -width / 2, right: width / 2, bottom: -height / 2, top: height / 2, near: 10, far: far)
        }
        translate(width / 2, height / 2, 0)
        rotateX(-Float.pi / 6)
        rotateY(Float.pi / 3)
        box(180)
    }
    func mousePressed() { showPerspective = !showPerspective }
}
