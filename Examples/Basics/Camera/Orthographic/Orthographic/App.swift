import metaphor

@main
final class Orthographic: Sketch {
    var showPerspective = false
    var config: SketchConfig { SketchConfig(title: "Orthographic", width: 600, height: 360) }
    func setup() { noStroke(); fill(255) }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(128, 128, 128, 0, 0, -1)
        background(0)
        let far = map(mouseX, 0, width, 120, 400)
        if showPerspective {
            perspective(Float.pi / 3, width / height, 10, far)
        } else {
            ortho(-width / 2, width / 2, -height / 2, height / 2, 10, far)
        }
        translate3D(width / 2, height / 2, 0)
        rotateX(-Float.pi / 6)
        rotateY(Float.pi / 3)
        box(180)
    }
    func mousePressed() { showPerspective = !showPerspective }
}
