import metaphor

@main
final class Coordinates: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360,title: "Coordinates") }
    func setup() { noLoop() }
    func draw() {
        background(0)
        noFill()
        stroke(255)
        point(320, 180)
        point(320, 90)
        stroke(0, 153, 255)
        line(0, 120, 640, 120)
        stroke(255, 153, 0)
        rect(160, 36, 320, 288)
    }
}
