import metaphor

struct GroundSegment {
    var x1: Float, y1: Float, x2: Float, y2: Float
    var x: Float, y: Float, len: Float, rot: Float

    init(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        x = (x1 + x2) / 2; y = (y1 + y2) / 2
        len = sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
        rot = atan2(y2 - y1, x2 - x1)
    }
}

@main
final class Reflection2: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Reflection 2", width: 640, height: 360)
    }

    var orbX: Float = 50, orbY: Float = 50
    var orbVX: Float = 0.5, orbVY: Float = 0
    let orbR: Float = 3
    let damping: Float = 0.8
    let gravityY: Float = 0.05
    let segments = 40
    var ground: [GroundSegment] = []

    func setup() {
        var peakHeights: [Float] = []
        for _ in 0...segments {
            peakHeights.append(random(height - 40, height - 30))
        }
        let segs = Float(segments)
        for i in 0..<segments {
            ground.append(GroundSegment(
                width / segs * Float(i), peakHeights[i],
                width / segs * Float(i + 1), peakHeights[i + 1]
            ))
        }
    }

    func draw() {
        noStroke()
        fill(0, 15)
        rect(0, 0, width, height)
        orbVY += gravityY
        orbX += orbVX; orbY += orbVY
        noStroke()
        fill(200)
        ellipse(orbX, orbY, orbR * 2, orbR * 2)
        if orbX > width - orbR { orbX = width - orbR; orbVX *= -damping }
        else if orbX < orbR { orbX = orbR; orbVX *= -damping }
        for g in ground {
            let deltaX = orbX - g.x
            let deltaY = orbY - g.y
            let cosine = cos(g.rot)
            let sine = sin(g.rot)
            let groundXTemp = cosine * deltaX + sine * deltaY
            var groundYTemp = cosine * deltaY - sine * deltaX
            var velocityXTemp = cosine * orbVX + sine * orbVY
            var velocityYTemp = cosine * orbVY - sine * orbVX
            if groundYTemp > -orbR && orbX > g.x1 && orbX < g.x2 {
                groundYTemp = -orbR
                velocityYTemp *= -1.0
                velocityYTemp *= damping
            }
            let newDX = cosine * groundXTemp - sine * groundYTemp
            let newDY = cosine * groundYTemp + sine * groundXTemp
            orbVX = cosine * velocityXTemp - sine * velocityYTemp
            orbVY = cosine * velocityYTemp + sine * velocityXTemp
            orbX = g.x + newDX
            orbY = g.y + newDY
        }
        fill(127)
        beginShape()
        for g in ground {
            vertex(g.x1, g.y1)
            vertex(g.x2, g.y2)
        }
        vertex(ground[segments - 1].x2, height)
        vertex(ground[0].x1, height)
        endShape(.close)
    }
}
