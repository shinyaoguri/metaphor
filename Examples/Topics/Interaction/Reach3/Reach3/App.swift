import metaphor

@main
final class Reach3: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Reach 3")
    }

    let numSegments = 8
    var x = [Float](repeating: 0, count: 8)
    var y = [Float](repeating: 0, count: 8)
    var angle = [Float](repeating: 0, count: 8)
    let segLength: Float = 26
    var targetX: Float = 0
    var targetY: Float = 0
    var ballX: Float = 50
    var ballY: Float = 50
    var ballXDirection: Float = 1
    var ballYDirection: Float = -1

    func setup() {
        strokeWeight(20)
        stroke(255, 100)
        noFill()
        x[numSegments - 1] = width / 2
        y[numSegments - 1] = height
    }

    func draw() {
        background(0)
        strokeWeight(20)
        ballX += 1.0 * ballXDirection
        ballY += 0.8 * ballYDirection
        if ballX > width - 25 || ballX < 25 { ballXDirection *= -1 }
        if ballY > height - 25 || ballY < 25 { ballYDirection *= -1 }
        ellipse(ballX, ballY, 30, 30)

        reachSegment(0, ballX, ballY)
        for i in 1..<numSegments {
            reachSegment(i, targetX, targetY)
        }
        for i in stride(from: numSegments - 1, through: 1, by: -1) {
            positionSegment(i, i - 1)
        }
        for i in 0..<numSegments {
            segment(x[i], y[i], angle[i], Float((i + 1) * 2))
        }
    }

    func positionSegment(_ a: Int, _ b: Int) {
        x[b] = x[a] + cos(angle[a]) * segLength
        y[b] = y[a] + sin(angle[a]) * segLength
    }

    func reachSegment(_ i: Int, _ xin: Float, _ yin: Float) {
        let dx = xin - x[i]
        let dy = yin - y[i]
        angle[i] = atan2(dy, dx)
        targetX = xin - cos(angle[i]) * segLength
        targetY = yin - sin(angle[i]) * segLength
    }

    func segment(_ sx: Float, _ sy: Float, _ a: Float, _ sw: Float) {
        strokeWeight(sw)
        pushMatrix()
        translate(sx, sy)
        rotate(a)
        line(0, 0, segLength, 0)
        popMatrix()
    }
}
