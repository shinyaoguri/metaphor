import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Topics/Vectors/BouncingBall
// The original .pde is not bundled — see Examples/NOTICE.md.

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
