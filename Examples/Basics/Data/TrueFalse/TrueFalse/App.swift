import metaphor

@main
final class TrueFalse: Sketch {
    var config: SketchConfig { SketchConfig(title: "True/False", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        background(0)
        stroke(255)
        let d: Float = 20
        let middle = width / 2
        var b = false
        var i = d
        while i <= width {
            if i < middle {
                b = true
            } else {
                b = false
            }
            if b {
                line(i, d, i, height - d)
            }
            if !b {
                line(middle, i - middle + d, width - d, i - middle + d)
            }
            i += d
        }
    }
}
