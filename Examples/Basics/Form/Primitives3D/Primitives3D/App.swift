import metaphor

@main
final class Primitives3D: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Primitives 3D") }
    func setup() { noLoop() }
    func draw() {
        background(0)
        lights()
        noStroke()
        push()
        translate(130, height / 2, 0)
        rotateY(1.25)
        rotateX(-0.4)
        box(100)
        pop()

        noFill()
        stroke(255)
        push()
        translate(500, height * 0.35, -200)
        sphere(280)
        pop()
    }
}
