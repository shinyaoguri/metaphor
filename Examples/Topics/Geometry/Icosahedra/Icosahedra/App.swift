import metaphor

struct Icosahedron {
    var topPoint: (Float, Float, Float) = (0, 0, 0)
    var topPent: [(Float, Float, Float)] = Array(repeating: (0, 0, 0), count: 5)
    var bottomPoint: (Float, Float, Float) = (0, 0, 0)
    var bottomPent: [(Float, Float, Float)] = Array(repeating: (0, 0, 0), count: 5)

    init(radius: Float) {
        let c = dist2D(cos(0) * radius, sin(0) * radius,
                       cos(radians(72)) * radius, sin(radians(72)) * radius)
        let b = radius
        let a = sqrt(max(c * c - b * b, 0))
        let triHt = sqrt(max(c * c - (c / 2) * (c / 2), 0))

        var angle: Float = 0
        for i in 0..<5 {
            topPent[i] = (cos(angle) * radius, sin(angle) * radius, triHt / 2.0)
            angle += radians(72)
        }
        topPoint = (0, 0, triHt / 2.0 + a)

        angle = radians(36)
        for i in 0..<5 {
            bottomPent[i] = (cos(angle) * radius, sin(angle) * radius, -triHt / 2.0)
            angle += radians(72)
        }
        bottomPoint = (0, 0, -(triHt / 2.0 + a))
    }

    func dist2D(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
        let dx = x2 - x1
        let dy = y2 - y1
        return sqrt(dx * dx + dy * dy)
    }

    func radians(_ deg: Float) -> Float { deg * .pi / 180 }
}

@main
final class Icosahedra: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Icosahedra", width: 640, height: 360)
    }

    var ico: Icosahedron!

    func setup() {
        ico = Icosahedron(radius: 75)
    }

    func draw() {
        background(0)
        lights()
        translate(width / 2, height / 2)

        // Left: wireframe red
        pushMatrix()
        translate(-width / 3.5, 0)
        rotateX(Float(frameCount) * .pi / 185)
        rotateY(Float(frameCount) * .pi / -200)
        stroke(170, 0, 0)
        noFill()
        drawIco(ico)
        popMatrix()

        // Center: yellow filled with purple stroke
        pushMatrix()
        rotateX(Float(frameCount) * .pi / 200)
        rotateY(Float(frameCount) * .pi / 300)
        stroke(150, 0, 180)
        fill(170, 170, 0)
        drawIco(ico)
        popMatrix()

        // Right: blue filled, no stroke
        pushMatrix()
        translate(width / 3.5, 0)
        rotateX(Float(frameCount) * .pi / -200)
        rotateY(Float(frameCount) * .pi / 200)
        noStroke()
        fill(0, 0, 185)
        drawIco(ico)
        popMatrix()
    }

    func drawIco(_ ico: Icosahedron) {
        for i in 0..<5 {
            let next = (i + 1) % 5

            // Top cap
            beginShape()
            vertex(ico.topPent[i].0, ico.topPent[i].1, ico.topPent[i].2)
            vertex(ico.topPoint.0, ico.topPoint.1, ico.topPoint.2)
            vertex(ico.topPent[next].0, ico.topPent[next].1, ico.topPent[next].2)
            endShape(.close)

            // Bottom cap
            beginShape()
            vertex(ico.bottomPent[i].0, ico.bottomPent[i].1, ico.bottomPent[i].2)
            vertex(ico.bottomPoint.0, ico.bottomPoint.1, ico.bottomPoint.2)
            vertex(ico.bottomPent[next].0, ico.bottomPent[next].1, ico.bottomPent[next].2)
            endShape(.close)
        }

        // Body triangles
        for i in 0..<5 {
            let next1 = (i + 1) % 5
            let next2 = (i + 2) % 5

            beginShape()
            vertex(ico.topPent[i].0, ico.topPent[i].1, ico.topPent[i].2)
            vertex(ico.bottomPent[next1].0, ico.bottomPent[next1].1, ico.bottomPent[next1].2)
            vertex(ico.bottomPent[next2].0, ico.bottomPent[next2].1, ico.bottomPent[next2].2)
            endShape(.close)

            beginShape()
            vertex(ico.bottomPent[next2].0, ico.bottomPent[next2].1, ico.bottomPent[next2].2)
            vertex(ico.topPent[i].0, ico.topPent[i].1, ico.topPent[i].2)
            vertex(ico.topPent[next1].0, ico.topPent[next1].1, ico.topPent[next1].2)
            endShape(.close)
        }
    }
}
