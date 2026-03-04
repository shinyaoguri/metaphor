import metaphor

@main
final class Reach1: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Reach 1", width: 640, height: 360)
    }

    let segLength: Float = 80
    var x: Float = 0, y: Float = 0
    var x2: Float = 0, y2: Float = 0

    func setup() {
        strokeWeight(20)
        stroke(255, 100)
        x = width / 2
        y = height / 2
        x2 = x
        y2 = y
    }

    func draw() {
        background(0)
        let dx = mouseX - x
        let dy = mouseY - y
        let angle1 = atan2(dy, dx)
        let tx = mouseX - cos(angle1) * segLength
        let ty = mouseY - sin(angle1) * segLength
        let dx2 = tx - x2
        let dy2 = ty - y2
        let angle2 = atan2(dy2, dx2)
        x = x2 + cos(angle2) * segLength
        y = y2 + sin(angle2) * segLength
        segment(x, y, angle1)
        segment(x2, y2, angle2)
    }

    func segment(_ sx: Float, _ sy: Float, _ a: Float) {
        pushMatrix()
        translate(sx, sy)
        rotate(a)
        line(0, 0, segLength, 0)
        popMatrix()
    }
}
