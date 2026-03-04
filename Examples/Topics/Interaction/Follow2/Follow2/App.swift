import metaphor

@main
final class Follow2: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Follow 2")
    }

    var x: [Float] = [0, 0]
    var y: [Float] = [0, 0]
    let segLength: Float = 50

    func setup() {
        strokeWeight(20)
        stroke(255, 100)
    }

    func draw() {
        background(0)
        dragSegment(0, mouseX, mouseY)
        dragSegment(1, x[0], y[0])
    }

    func dragSegment(_ i: Int, _ xin: Float, _ yin: Float) {
        let dx = xin - x[i]
        let dy = yin - y[i]
        let angle = atan2(dy, dx)
        x[i] = xin - cos(angle) * segLength
        y[i] = yin - sin(angle) * segLength
        segment(x[i], y[i], angle)
    }

    func segment(_ sx: Float, _ sy: Float, _ a: Float) {
        pushMatrix()
        translate(sx, sy)
        rotate(a)
        line(0, 0, segLength, 0)
        popMatrix()
    }
}
