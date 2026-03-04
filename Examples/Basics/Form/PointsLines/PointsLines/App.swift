import metaphor

@main
final class PointsLines: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Points and Lines") }
    func setup() { noLoop() }
    func draw() {
        let d: Float = 70
        let p1 = d
        let p2 = p1 + d
        let p3 = p2 + d
        let p4 = p3 + d

        background(0)
        translate(140, 0)

        // Draw gray box
        stroke(153)
        line(p3, p3, p2, p3)
        line(p2, p3, p2, p2)
        line(p2, p2, p3, p2)
        line(p3, p2, p3, p3)

        // Draw white points
        stroke(255)
        point(p1, p1)
        point(p1, p3)
        point(p2, p4)
        point(p3, p1)
        point(p4, p2)
        point(p4, p4)
    }
}
