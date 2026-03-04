import metaphor

@main
final class Primitives3D: Sketch {
    var config: SketchConfig { SketchConfig(title: "Primitives 3D", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        background(0)
        ambientLight(128, 128, 128)
        directionalLight(128, 128, 128, 0, 0, -1)

        noStroke()
        push()
        translate3D(130, height / 2, 0)
        rotateY(1.25)
        rotateX(-0.4)
        box(100)
        pop()

        noFill()
        stroke(255)
        push()
        translate3D(500, height * 0.35, -200)
        sphere(280)
        pop()
    }
}
