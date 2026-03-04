import metaphor

@main
final class BouncingBall: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Bouncing Ball")
    }

    var locX: Float = 100, locY: Float = 100
    var velX: Float = 1.5, velY: Float = 2.1
    let gravityY: Float = 0.2

    func draw() {
        background(0)
        locX += velX
        locY += velY
        velY += gravityY
        if locX > width || locX < 0 { velX *= -1 }
        if locY > height {
            velY *= -0.95
            locY = height
        }
        stroke(255)
        strokeWeight(2)
        fill(127)
        ellipse(locX, locY, 48, 48)
    }
}
