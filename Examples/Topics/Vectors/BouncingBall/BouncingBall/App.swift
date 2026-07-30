import metaphor

// Bouncing Ball
// Bounce simulation using Vec2 to represent position, velocity, and gravity.

@main
final class BouncingBall: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Bouncing Ball")
    }

    var location = Vec2(100, 100)
    var velocity = Vec2(1.5, 2.1)
    let gravity = Vec2(0, 0.2)

    func draw() {
        background(0)

        location += velocity
        velocity += gravity

        if location.x > width || location.x < 0 {
            velocity.x *= -1
        }
        if location.y > height {
            velocity.y *= -0.95
            location.y = height
        }

        stroke(255)
        strokeWeight(2)
        fill(127)
        ellipse(location.x, location.y, 48, 48)
    }
}
