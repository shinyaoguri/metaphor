import metaphor

struct BBall {
    var x: Float
    var y: Float
    var diameter: Float
    var vx: Float = 0
    var vy: Float = 0
}

@main
final class BouncyBubbles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Bouncy Bubbles")
    }

    let numBalls = 12
    let spring: Float = 0.05
    let gravity: Float = 0.03
    let friction: Float = -0.9
    var balls: [BBall] = []

    func setup() {
        for _ in 0..<numBalls {
            balls.append(BBall(
                x: random(width), y: random(height),
                diameter: random(30, 70)
            ))
        }
        noStroke()
        fill(255, 204)
    }

    func draw() {
        background(0)
        for i in 0..<numBalls {
            for j in (i + 1)..<numBalls {
                let dx = balls[j].x - balls[i].x
                let dy = balls[j].y - balls[i].y
                let distance = sqrt(dx * dx + dy * dy)
                let minDist = balls[j].diameter / 2 + balls[i].diameter / 2
                if distance < minDist {
                    let angle = atan2(dy, dx)
                    let targetX = balls[i].x + cos(angle) * minDist
                    let targetY = balls[i].y + sin(angle) * minDist
                    let ax = (targetX - balls[j].x) * spring
                    let ay = (targetY - balls[j].y) * spring
                    balls[i].vx -= ax
                    balls[i].vy -= ay
                    balls[j].vx += ax
                    balls[j].vy += ay
                }
            }
            balls[i].vy += gravity
            balls[i].x += balls[i].vx
            balls[i].y += balls[i].vy
            if balls[i].x + balls[i].diameter / 2 > width {
                balls[i].x = width - balls[i].diameter / 2
                balls[i].vx *= friction
            } else if balls[i].x - balls[i].diameter / 2 < 0 {
                balls[i].x = balls[i].diameter / 2
                balls[i].vx *= friction
            }
            if balls[i].y + balls[i].diameter / 2 > height {
                balls[i].y = height - balls[i].diameter / 2
                balls[i].vy *= friction
            } else if balls[i].y - balls[i].diameter / 2 < 0 {
                balls[i].y = balls[i].diameter / 2
                balls[i].vy *= friction
            }
            ellipse(balls[i].x, balls[i].y, balls[i].diameter, balls[i].diameter)
        }
    }
}
