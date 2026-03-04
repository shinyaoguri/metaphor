import metaphor

@main
final class RegularPolygon: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Regular Polygon") }
    func draw() {
        background(102)

        push()
        translate(width * 0.2, height * 0.5)
        rotate(Float(frameCount) / 200.0)
        drawPolygon(0, 0, 82, 3)
        pop()

        push()
        translate(width * 0.5, height * 0.5)
        rotate(Float(frameCount) / 50.0)
        drawPolygon(0, 0, 80, 20)
        pop()

        push()
        translate(width * 0.8, height * 0.5)
        rotate(Float(frameCount) / -100.0)
        drawPolygon(0, 0, 70, 7)
        pop()
    }
    private func drawPolygon(_ x: Float, _ y: Float, _ radius: Float, _ npoints: Int) {
        let angle = Float.pi * 2 / Float(npoints)
        beginShape()
        var a: Float = 0
        while a < Float.pi * 2 {
            let sx = x + cos(a) * radius
            let sy = y + sin(a) * radius
            vertex(sx, sy)
            a += angle
        }
        endShape(.close)
    }
}
