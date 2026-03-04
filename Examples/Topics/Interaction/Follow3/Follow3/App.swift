import metaphor

@main
final class Follow3: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Follow 3")
    }

    var x = [Float](repeating: 0, count: 20)
    var y = [Float](repeating: 0, count: 20)
    let segLength: Float = 18

    func setup() {
        strokeWeight(9)
        stroke(255, 100)
    }

    func draw() {
        background(0)
        dragSegment(0, mouseX, mouseY)
        for i in 0..<x.count - 1 {
            dragSegment(i + 1, x[i], y[i])
        }
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
