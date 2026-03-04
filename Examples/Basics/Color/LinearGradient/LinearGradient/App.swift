import metaphor

@main
final class LinearGradient: Sketch {
    let Y_AXIS = 1
    let X_AXIS = 2
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Linear Gradient") }
    func setup() { noLoop() }
    func draw() {
        let b1 = Color.white
        let b2 = Color.black
        let c1 = Color(r: 204.0/255, g: 102.0/255, b: 0)
        let c2 = Color(r: 0, g: 102.0/255, b: 153.0/255)
        setGradient(0, 0, width / 2, height, b1, b2, X_AXIS)
        setGradient(width / 2, 0, width / 2, height, b2, b1, X_AXIS)
        setGradient(50, 90, 540, 80, c1, c2, Y_AXIS)
        setGradient(50, 190, 540, 80, c2, c1, X_AXIS)
    }
    private func setGradient(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ c1: Color, _ c2: Color, _ axis: Int) {
        noFill()
        if axis == Y_AXIS {
            var i = y
            while i <= y + h {
                let inter = map(i, y, y + h, 0, 1)
                let c = lerpColor(c1, c2, inter)
                stroke(c)
                line(x, i, x + w, i)
                i += 1
            }
        } else if axis == X_AXIS {
            var i = x
            while i <= x + w {
                let inter = map(i, x, x + w, 0, 1)
                let c = lerpColor(c1, c2, inter)
                stroke(c)
                line(i, y, i, y + h)
                i += 1
            }
        }
    }
}
