import metaphor

@main
final class ColorVariables: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Color Variables") }
    func setup() { noLoop() }
    func draw() {
        noStroke()
        background(51, 0, 0)
        let inside = Color(r: 204.0/255, g: 102.0/255, b: 0)
        let middle = Color(r: 204.0/255, g: 153.0/255, b: 0)
        let outside = Color(r: 153.0/255, g: 51.0/255, b: 0)

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
