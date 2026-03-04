import metaphor

@main
final class Reflection1: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Reflection 1")
    }

    var base1x: Float = 0, base1y: Float = 0
    var base2x: Float = 0, base2y: Float = 0
    var coords: [(Float, Float)] = []
    var px: Float = 0, py: Float = 0
    var vx: Float = 0, vy: Float = 0
    let r: Float = 6
    let speed: Float = 3.5

    func setup() {
        fill(128)
        base1x = 0; base1y = height - 150
        base2x = width; base2y = height
        createGroundCoords()
        px = width / 2; py = 0
        let angle = Float.random(in: 0..<Float.pi * 2)
        vx = cos(angle) * speed; vy = sin(angle) * speed
    }

    func draw() {
        fill(0, 12)
        noStroke()
        rect(0, 0, width, height)
        fill(200)
        quad(base1x, base1y, base2x, base2y, base2x, height, 0, height)
        let baseDx = base2x - base1x
        let baseDy = base2y - base1y
        let baseLen = sqrt(baseDx * baseDx + baseDy * baseDy)
        let ndx = baseDx / baseLen
        let ndy = baseDy / baseLen
        let normalX = -ndy
        let normalY = ndx
        noStroke()
        fill(255)
        ellipse(px, py, r * 2, r * 2)
        px += vx; py += vy
        let incX = -vx / speed
        let incY = -vy / speed
        for coord in coords {
            let dx = px - coord.0
            let dy = py - coord.1
            if sqrt(dx * dx + dy * dy) < r {
                let dot = incX * normalX + incY * normalY
                vx = (2 * normalX * dot - incX) * speed
                vy = (2 * normalY * dot - incY) * speed
                stroke(255, 128, 0)
                line(px, py, px - normalX * 100, py - normalY * 100)
            }
        }
        if px > width - r { px = width - r; vx *= -1 }
        if px < r { px = r; vx *= -1 }
        if py < r {
            py = r; vy *= -1
            base1y = random(height - 100, height)
            base2y = random(height - 100, height)
            createGroundCoords()
        }
    }

    func createGroundCoords() {
        let dx = base2x - base1x
        let dy = base2y - base1y
        let baseLength = sqrt(dx * dx + dy * dy)
        let count = Int(ceil(baseLength))
        coords = []
        for i in 0..<count {
            coords.append((
                base1x + dx / baseLength * Float(i),
                base1y + dy / baseLength * Float(i)
            ))
        }
    }
}
