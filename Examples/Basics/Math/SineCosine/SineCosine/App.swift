import metaphor

@main
final class SineCosine: Sketch {
    var angle1: Float = 0; var angle2: Float = 0
    let scalar: Float = 70
    var config: SketchConfig { SketchConfig(title: "Sine Cosine", width: 640, height: 360) }
    func setup() { noStroke(); rectMode(.center) }
    func draw() {
        background(0)
        let ang1 = radians(angle1); let ang2 = radians(angle2)
        let x1 = width / 2 + scalar * cos(ang1)
        let x2 = width / 2 + scalar * cos(ang2)
        let y1 = height / 2 + scalar * sin(ang1)
        let y2 = height / 2 + scalar * sin(ang2)
        fill(255); rect(width * 0.5, height * 0.5, 140, 140)
        fill(0, 102, 153)
        ellipse(x1, height * 0.5 - 120, scalar, scalar)
        ellipse(x2, height * 0.5 + 120, scalar, scalar)
        fill(255, 204, 0)
        ellipse(width * 0.5 - 120, y1, scalar, scalar)
        ellipse(width * 0.5 + 120, y2, scalar, scalar)
        angle1 += 2; angle2 += 3
    }
}
