import metaphor

struct FMover {
    var px: Float, py: Float
    var vx: Float = 0, vy: Float = 0
    var ax: Float = 0, ay: Float = 0
    var mass: Float
}

@main
final class ForcesWithVectors: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Forces With Vectors") }

    var movers: [FMover] = []
    let liquidY: Float = 180
    let dragCoeff: Float = 0.1

    func setup() {
        resetMovers()
    }

    func draw() {
        background(0)
        noStroke()
        fill(127)
        rect(0, liquidY, width, height / 2)
        for i in 0..<movers.count {
            if movers[i].py > liquidY {
                let speed = sqrt(movers[i].vx * movers[i].vx + movers[i].vy * movers[i].vy)
                let dragMag = dragCoeff * speed * speed
                var dx = -movers[i].vx, dy = -movers[i].vy
                let m = sqrt(dx * dx + dy * dy)
                if m > 0 { dx = dx / m * dragMag; dy = dy / m * dragMag }
                movers[i].ax += dx / movers[i].mass; movers[i].ay += dy / movers[i].mass
            }
            movers[i].ay += 0.1
            movers[i].vx += movers[i].ax; movers[i].vy += movers[i].ay
            movers[i].px += movers[i].vx; movers[i].py += movers[i].vy
            movers[i].ax = 0; movers[i].ay = 0
            if movers[i].py > height {
                movers[i].vy *= -0.9; movers[i].py = height
            }
            stroke(255); strokeWeight(2); fill(255, 200)
            ellipse(movers[i].px, movers[i].py, movers[i].mass * 16, movers[i].mass * 16)
        }
        fill(255); noStroke()
        textSize(12)
        text("click mouse to reset", 10, 30)
    }

    func resetMovers() {
        movers = []
        for i in 0..<10 {
            movers.append(FMover(px: 40 + Float(i) * 70, py: 0, mass: random(0.5, 3)))
        }
    }

    func mousePressed() { resetMovers() }
}
