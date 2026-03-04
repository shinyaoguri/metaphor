import metaphor

@main
final class Star: Sketch {
    var config: SketchConfig { SketchConfig(title: "Star", width: 640, height: 360) }
    func draw() {
        background(102)

        push()
        translate(width * 0.2, height * 0.5)
        rotate(Float(frameCount) / 200.0)
        drawStar(0, 0, 5, 70, 3)
        pop()

        push()
        translate(width * 0.5, height * 0.5)
        rotate(Float(frameCount) / 400.0)
        drawStar(0, 0, 80, 100, 40)
        pop()

        push()
        translate(width * 0.8, height * 0.5)
        rotate(Float(frameCount) / -100.0)
        drawStar(0, 0, 30, 70, 5)
        pop()
    }
    private func drawStar(_ x: Float, _ y: Float, _ radius1: Float, _ radius2: Float, _ npoints: Int) {
        let angle = Float.pi * 2 / Float(npoints)
        let halfAngle = angle / 2.0
        beginShape()
        var a: Float = 0
        while a < Float.pi * 2 {
            var sx = x + cos(a) * radius2
            var sy = y + sin(a) * radius2
            vertex(sx, sy)
            sx = x + cos(a + halfAngle) * radius1
            sy = y + sin(a + halfAngle) * radius1
            vertex(sx, sy)
            a += angle
        }
        endShape(.close)
    }
}
