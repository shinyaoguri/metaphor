import metaphor

@main
final class Tree: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Tree")
    }

    var theta: Float = 0

    func setup() {}

    func draw() {
        background(0)
        stroke(255)
        let a = (mouseX / width) * 90
        theta = radians(a)
        translate(width / 2, height)
        line(0, 0, 0, -120)
        translate(0, -120)
        branch(120)
    }

    func branch(_ h: Float) {
        let len = h * 0.66
        if len > 2 {
            pushMatrix()
            rotate(theta)
            line(0, 0, 0, -len)
            translate(0, -len)
            branch(len)
            popMatrix()

            pushMatrix()
            rotate(-theta)
            line(0, 0, 0, -len)
            translate(0, -len)
            branch(len)
            popMatrix()
        }
    }
}
