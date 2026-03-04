import metaphor

class Egg {
    var x: Float; var y: Float; var tilt: Float = 0; var angle: Float = 0
    var scalar: Float; var range: Float
    init(_ xpos: Float, _ ypos: Float, _ r: Float, _ s: Float) {
        x = xpos; y = ypos; range = r; scalar = s / 100
    }
    func wobble() { tilt = cos(angle) / range; angle += 0.1 }
}

class Ring {
    var x: Float = 0; var y: Float = 0; var diameter: Float = 1; var on = false
    func start(_ xpos: Float, _ ypos: Float) { x = xpos; y = ypos; on = true; diameter = 1 }
    func grow(_ w: Float) { if on { diameter += 0.5; if diameter > w * 2 { diameter = 0 } } }
}

class EggRing {
    var ovoid: Egg; var circle = Ring()
    init(_ x: Float, _ y: Float, _ t: Float, _ sp: Float) {
        ovoid = Egg(x, y, t, sp)
        circle.start(x, y - sp / 2)
    }
}

@main
final class CompositeObjects: Sketch {
    var er1: EggRing!; var er2: EggRing!
    var config: SketchConfig { SketchConfig(title: "Composite Objects", width: 640, height: 360) }
    func setup() {
        er1 = EggRing(width * 0.45, height * 0.5, 2, 120)
        er2 = EggRing(width * 0.65, height * 0.8, 10, 180)
    }
    func draw() {
        background(0)
        for er in [er1!, er2!] {
            er.ovoid.wobble()
            noStroke(); fill(255)
            push()
            translate(er.ovoid.x, er.ovoid.y)
            rotate(er.ovoid.tilt)
            scale(er.ovoid.scalar)
            beginShape()
            vertex(0, -100)
            bezier(0, -100, 25, -100, 40, -65, 40, -40)
            // Simplified egg shape
            ellipse(0, -50, 80, 100)
            endShape()
            pop()
            er.circle.grow(width)
            if er.circle.on {
                noFill(); strokeWeight(4); stroke(155, 153)
                ellipse(er.circle.x, er.circle.y, er.circle.diameter, er.circle.diameter)
            }
        }
    }
}
