import metaphor

@main
final class MovingOnCurves: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Moving On Curves")
    }

    var beginX: Float = 20, beginY: Float = 10
    var endX: Float = 570, endY: Float = 320
    var distX: Float = 0, distY: Float = 0
    let exponent: Float = 4
    var x: Float = 0, y: Float = 0
    let step: Float = 0.01
    var pct: Float = 0

    func setup() {
        noStroke()
        distX = endX - beginX
        distY = endY - beginY
    }

    func draw() {
        fill(0, 2)
        rect(0, 0, width, height)
        pct += step
        if pct < 1.0 {
            x = beginX + pct * distX
            y = beginY + pow(pct, exponent) * distY
        }
        fill(255)
        ellipse(x, y, 20, 20)
    }

    func mousePressed() {
        pct = 0
        beginX = x
        beginY = y
        endX = mouseX
        endY = mouseY
        distX = endX - beginX
        distY = endY - beginY
    }
}
