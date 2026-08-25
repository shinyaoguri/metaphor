import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Math/PolarToCartesian
// The original .pde is not bundled — see Examples/NOTICE.md.

@main
final class PolarToCartesian: Sketch {
    var r: Float = 0; var theta: Float = 0; var thetaVel: Float = 0; let thetaAcc: Float = 0.0001
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Polar to Cartesian") }
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
