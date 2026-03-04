import metaphor

@main
final class OnOff: Sketch {
    var spin: Float = 0
    var config: SketchConfig { SketchConfig(title: "On Off", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        background(51)
        if !isMousePressed {
            ambientLight(128, 128, 128)
            directionalLight(128, 128, 128, 0, 0, -1)
        }
        spin += 0.01
        push()
        translate3D(width / 2, height / 2, 0)
        rotateX(Float.pi / 9)
        rotateY(Float.pi / 5 + spin)
        box(150)
        pop()
    }
}
