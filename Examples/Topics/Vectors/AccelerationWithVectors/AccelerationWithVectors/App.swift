import metaphor

// Acceleration With Vectors
// Calculate acceleration toward the mouse using Vec2's setMag()/limit() methods.
// Processing's PVector code (sub → setMag → add → limit) translates nearly 1:1.

@main
final class AccelerationWithVectors: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Acceleration With Vectors")
    }

    var location = Vec2.zero
    var velocity = Vec2.zero
    let topspeed: Float = 5

    func setup() {
        location = Vec2(width / 2, height / 2)
    }

    func draw() {
        background(0)

        // Compute a vector that points from location to mouse, with magnitude 0.2
        let mouse = Vec2(mouseX, mouseY)
        var acceleration = mouse - location
        acceleration.setMag(0.2)

        // Velocity changes by acceleration and is limited by topspeed
        velocity += acceleration
        velocity.limit(topspeed)
        location += velocity

        stroke(255)
        strokeWeight(2)
        fill(127)
        ellipse(location.x, location.y, 48, 48)
    }
}
