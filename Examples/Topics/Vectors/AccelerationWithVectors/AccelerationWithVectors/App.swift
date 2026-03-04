import metaphor

@main
final class AccelerationWithVectors: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Acceleration With Vectors")
    }

    var locX: Float = 0, locY: Float = 0
    var velX: Float = 0, velY: Float = 0
    let topspeed: Float = 5

    func setup() {
        locX = width / 2
        locY = height / 2
    }

    func draw() {
        background(0)
        var accX = mouseX - locX
        var accY = mouseY - locY
        let mag = sqrt(accX * accX + accY * accY)
        if mag > 0 {
            accX = accX / mag * 0.2
            accY = accY / mag * 0.2
        }
        velX += accX
        velY += accY
        let velMag = sqrt(velX * velX + velY * velY)
        if velMag > topspeed {
            velX = velX / velMag * topspeed
            velY = velY / velMag * topspeed
        }
        locX += velX
        locY += velY
        stroke(255)
        strokeWeight(2)
        fill(127)
        ellipse(locX, locY, 48, 48)
    }
}
