import metaphor

@main
final class Follow1: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Follow 1")
    }

    var x: Float = 100
    var y: Float = 100
    var angle1: Float = 0
    let segLength: Float = 50

    func setup() {
        strokeWeight(20)
        stroke(255, 100)
    }

    func draw() {
        background(0)
        let dx = mouseX - x
        let dy = mouseY - y
        angle1 = atan2(dy, dx)
        x = mouseX - cos(angle1) * segLength
        y = mouseY - sin(angle1) * segLength
        segment(x, y, angle1)
        ellipse(x, y, 20, 20)
    }

    func segment(_ sx: Float, _ sy: Float, _ a: Float) {
        pushMatrix()
        translate(sx, sy)
        rotate(a)
        line(0, 0, segLength, 0)
        popMatrix()
    }
}
