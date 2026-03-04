import metaphor

@main
final class DepthSort: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "DepthSort", width: 640, height: 720)
    }

    func setup() {
        colorMode(.hsb, 100)
        frameRate(60)
    }

    func draw() {
        noStroke()
        background(0)

        translate(width / 2, height / 2, -300)
        scale(2)

        let rot = Float(frameCount)
        rotateZ(radians(90))
        rotateX(radians(rot / 60.0 * 10))
        rotateY(radians(rot / 60.0 * 30))

        blendMode(.add)

        for i in 0..<100 {
            let hue = map(Float(i % 10), 0, 10, 0, 100)
            fill(hue, 100, 100, 30)

            beginShape(.triangles)
            vertex(200, 50, -50)
            vertex(100, 100, 50)
            vertex(100, 0, 20)
            endShape()

            rotateY(radians(270.0 / 100))
        }
    }
}
