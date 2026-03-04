import metaphor

@main
final class PolarToCartesian: Sketch {
    var r: Float = 0; var theta: Float = 0; var thetaVel: Float = 0; let thetaAcc: Float = 0.0001
    var config: SketchConfig { SketchConfig(title: "Polar to Cartesian", width: 640, height: 360) }
    func setup() { r = height * 0.45; noStroke(); fill(200) }
    func draw() {
        background(0)
        translate(width / 2, height / 2)
        let x = r * cos(theta); let y = r * sin(theta)
        ellipseMode(.center)
        ellipse(x, y, 32, 32)
        thetaVel += thetaAcc; theta += thetaVel
    }
}
