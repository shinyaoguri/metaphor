import metaphor

@main
final class RotateXY: Sketch {
    var a: Float = 0
    var rSize: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Rotate XY") }
    func setup() {
        rSize = width / 6
        noStroke()
        fill(204, 204)
    }
    func draw() {
        background(126)
        a += 0.005
        if a > Float.pi * 2 { a = 0 }
        translate(width / 2, height / 2, 0)
        rotateX(a)
        rotateY(a * 2)
        fill(255)
        rect(-rSize, -rSize, rSize * 2, rSize * 2)
        rotateX(a * 1.001)
        rotateY(a * 2.002)
        fill(0)
        rect(-rSize, -rSize, rSize * 2, rSize * 2)
    }
}
