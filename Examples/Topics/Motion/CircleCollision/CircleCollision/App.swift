import metaphor

struct CollisionBall {
    var px: Float, py: Float
    var vx: Float, vy: Float
    var radius: Float, m: Float

    init(x: Float, y: Float, r: Float) {
        px = x; py = y; radius = r; m = r * 0.1
        let angle = Float.random(in: 0..<Float.pi * 2)
        vx = cos(angle) * 3; vy = sin(angle) * 3
    }
}

@main
final class CircleCollision: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Circle Collision", width: 640, height: 360)
    }

    var balls: [CollisionBall] = []

    func setup() {
        balls = [
            CollisionBall(x: 100, y: 200, r: 20),
            CollisionBall(x: 400, y: 200, r: 80)
        ]
    }

    func draw() {
        background(51)
        for i in 0..<balls.count {
            balls[i].px += balls[i].vx
            balls[i].py += balls[i].vy
            if balls[i].px > width - balls[i].radius {
                balls[i].px = width - balls[i].radius; balls[i].vx *= -1
            } else if balls[i].px < balls[i].radius {
                balls[i].px = balls[i].radius; balls[i].vx *= -1
            }
            if balls[i].py > height - balls[i].radius {
                balls[i].py = height - balls[i].radius; balls[i].vy *= -1
            } else if balls[i].py < balls[i].radius {
                balls[i].py = balls[i].radius; balls[i].vy *= -1
            }
        }
        checkCollision()
        noStroke()
        fill(204)
        for b in balls {
            ellipse(b.px, b.py, b.radius * 2, b.radius * 2)
        }
    }

    func checkCollision() {
        let dx = balls[1].px - balls[0].px
        let dy = balls[1].py - balls[0].py
        let dist = sqrt(dx * dx + dy * dy)
        let minDist = balls[0].radius + balls[1].radius
        if dist < minDist {
            let correction = (minDist - dist) / 2.0
            let nx = dx / dist
            let ny = dy / dist
            balls[1].px += nx * correction
            balls[1].py += ny * correction
            balls[0].px -= nx * correction
            balls[0].py -= ny * correction
            let theta = atan2(dy, dx)
            let sine = sin(theta)
            let cosine = cos(theta)
            let vTemp0x = cosine * balls[0].vx + sine * balls[0].vy
            let vTemp0y = cosine * balls[0].vy - sine * balls[0].vx
            let vTemp1x = cosine * balls[1].vx + sine * balls[1].vy
            let vTemp1y = cosine * balls[1].vy - sine * balls[1].vx
            let m0 = balls[0].m
            let m1 = balls[1].m
            let vFinal0x = ((m0 - m1) * vTemp0x + 2 * m1 * vTemp1x) / (m0 + m1)
            let vFinal0y = vTemp0y
            let vFinal1x = ((m1 - m0) * vTemp1x + 2 * m0 * vTemp0x) / (m0 + m1)
            let vFinal1y = vTemp1y
            balls[0].vx = cosine * vFinal0x - sine * vFinal0y
            balls[0].vy = cosine * vFinal0y + sine * vFinal0x
            balls[1].vx = cosine * vFinal1x - sine * vFinal1y
            balls[1].vy = cosine * vFinal1y + sine * vFinal1x
        }
    }
}
