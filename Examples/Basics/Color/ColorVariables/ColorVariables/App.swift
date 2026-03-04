import metaphor

@main
final class ColorVariables: Sketch {
    var config: SketchConfig { SketchConfig(title: "Color Variables", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        noStroke()
        background(51, 0, 0)
        let inside = Color(204.0/255, 102.0/255, 0)
        let middle = Color(204.0/255, 153.0/255, 0)
        let outside = Color(153.0/255, 51.0/255, 0)

        push()
        translate(80, 80)
        fill(outside)
        rect(0, 0, 200, 200)
        fill(middle)
        rect(40, 60, 120, 120)
        fill(inside)
        rect(60, 90, 80, 80)
        pop()

        push()
        translate(360, 80)
        fill(inside)
        rect(0, 0, 200, 200)
        fill(outside)
        rect(40, 60, 120, 120)
        fill(middle)
        rect(60, 90, 80, 80)
        pop()
    }
}
