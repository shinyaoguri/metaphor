import metaphor

@main
final class Morph: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Morph")
    }

    var circleVerts: [(Float, Float)] = []
    var squareVerts: [(Float, Float)] = []
    var morphVerts: [(Float, Float)] = []
    var state = false

    func setup() {
        var angle: Float = 0
        while angle < 360 {
            let rad = radians(angle - 135)
            circleVerts.append((cos(rad) * 100, sin(rad) * 100))
            morphVerts.append((0, 0))
            angle += 9
        }
        var x: Float = -50
        while x < 50 { squareVerts.append((x, -50)); x += 10 }
        var y: Float = -50
        while y < 50 { squareVerts.append((50, y)); y += 10 }
        x = 50
        while x > -50 { squareVerts.append((x, 50)); x -= 10 }
        y = 50
        while y > -50 { squareVerts.append((-50, y)); y -= 10 }
    }

    func draw() {
        background(51)
        var totalDistance: Float = 0
        for i in 0..<circleVerts.count {
            let target = state ? circleVerts[i] : squareVerts[i]
            morphVerts[i].0 = lerp(morphVerts[i].0, target.0, 0.1)
            morphVerts[i].1 = lerp(morphVerts[i].1, target.1, 0.1)
            let dx = target.0 - morphVerts[i].0
            let dy = target.1 - morphVerts[i].1
            totalDistance += sqrt(dx * dx + dy * dy)
        }
        if totalDistance < 0.1 { state = !state }
        translate(width / 2, height / 2)
        strokeWeight(4)
        beginShape()
        noFill()
        stroke(255)
        for v in morphVerts {
            vertex(v.0, v.1)
        }
        endShape(.close)
    }
}
