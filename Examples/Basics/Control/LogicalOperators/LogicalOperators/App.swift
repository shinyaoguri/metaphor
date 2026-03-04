import metaphor

@main
final class LogicalOperators: Sketch {
    var config: SketchConfig { SketchConfig(title: "Logical Operators", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        background(126)
        var test = false
        var i: Float = 5
        while i <= height {
            // Logical AND
            stroke(0)
            if i > 35 && i < 100 {
                line(width / 4, i, width / 2, i)
                test = false
            }
            // Logical OR
            stroke(76)
            if i <= 35 || i >= 100 {
                line(width / 2, i, width, i)
                test = true
            }
            if test {
                stroke(0)
                point(width / 3, i)
            }
            if !test {
                stroke(255)
                point(width / 4, i)
            }
            i += 5
        }
    }
}
