import metaphor

@main
final class MouseSignals: Sketch {
    var xvals: [Float] = []
    var yvals: [Float] = []
    var bvals: [Float] = []
    var config: SketchConfig { SketchConfig(title: "Mouse Signals", width: 640, height: 360) }
    func setup() {
        xvals = [Float](repeating: 0, count: Int(width))
        yvals = [Float](repeating: 0, count: Int(width))
        bvals = [Float](repeating: 0, count: Int(width))
    }
    func draw() {
        background(102)
        let w = Int(width)
        for i in 1..<w {
            xvals[i - 1] = xvals[i]
            yvals[i - 1] = yvals[i]
            bvals[i - 1] = bvals[i]
        }
        xvals[w - 1] = mouseX
        yvals[w - 1] = mouseY
        bvals[w - 1] = isMousePressed ? 0 : height / 3
        fill(255)
        noStroke()
        rect(0, height / 3, width, height / 3 + 1)
        for i in 1..<w {
            stroke(255)
            point(Float(i), map(xvals[i], 0, width, 0, height / 3 - 1))
            stroke(0)
            point(Float(i), height / 3 + yvals[i] / 3)
            stroke(255)
            line(Float(i), 2 * height / 3 + bvals[i], Float(i), 2 * height / 3 + bvals[i - 1])
        }
    }
}
