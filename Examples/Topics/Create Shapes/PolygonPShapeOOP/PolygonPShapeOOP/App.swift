import metaphor

/// PolygonPShapeOOP
///
/// Wrapping an MShape inside a custom class.
/// Two Star objects move across the screen independently.

struct Star {
    var s: MShape
    var x: Float
    var y: Float
    var speed: Float
}

@main
final class PolygonPShapeOOP: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PolygonPShapeOOP")
    }

    var s1: Star!
    var s2: Star!

    func setup() {
        s1 = makeStar()
        s2 = makeStar()
    }

    func makeStar() -> Star {
        let s = createShape()
        s.beginShape()
        s.fill(Color(gray: 1.0, alpha: 204.0 / 255.0))
        s.noStroke()
        s.vertex(0, -50)
        s.vertex(14, -20)
        s.vertex(47, -15)
        s.vertex(23, 7)
        s.vertex(29, 40)
        s.vertex(0, 25)
        s.vertex(-29, 40)
        s.vertex(-23, 7)
        s.vertex(-47, -15)
        s.vertex(-14, -20)
        s.endShape(.close)

        return Star(
            s: s,
            x: random(100, width - 100),
            y: random(100, height - 100),
            speed: random(0.5, 3)
        )
    }

    func draw() {
        background(51)

        displayStar(&s1)
        moveStar(&s1)

        displayStar(&s2)
        moveStar(&s2)
    }

    func displayStar(_ star: inout Star) {
        pushMatrix()
        translate(star.x, star.y)
        shape(star.s)
        popMatrix()
    }

    func moveStar(_ star: inout Star) {
        star.x += star.speed
        if star.x > width + 100 {
            star.x = -100
        }
    }
}
