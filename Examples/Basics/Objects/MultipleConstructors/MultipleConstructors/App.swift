import metaphor

class SpotShape {
    var x: Float; var y: Float; var radius: Float
    init() { radius = 40; x = 0; y = 0 }
    init(_ xpos: Float, _ ypos: Float, _ r: Float) { x = xpos; y = ypos; radius = r }
}

@main
final class MultipleConstructors: Sketch {
    var sp1: SpotShape!; var sp2: SpotShape!
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Multiple Constructors") }
    func setup() {
        background(204)
        noLoop()
        sp1 = SpotShape()
        sp1.x = width * 0.25; sp1.y = height * 0.5
        sp2 = SpotShape(width * 0.5, height * 0.5, 120)
    }
    func draw() {
        ellipse(sp1.x, sp1.y, sp1.radius * 2, sp1.radius * 2)
        ellipse(sp2.x, sp2.y, sp2.radius * 2, sp2.radius * 2)
    }
}
