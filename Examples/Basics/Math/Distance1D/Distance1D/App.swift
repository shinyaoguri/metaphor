import metaphor

@main
final class Distance1D: Sketch {
    var xpos1: Float = 0; var xpos2: Float = 0; var xpos3: Float = 0; var xpos4: Float = 0
    let thin: Float = 8; let thick: Float = 36
    var config: SketchConfig { SketchConfig(title: "Distance 1D", width: 640, height: 360) }
    func setup() {
        noStroke()
        xpos1 = width / 2; xpos2 = width / 2; xpos3 = width / 2; xpos4 = width / 2
    }
    func draw() {
        background(0)
        let mx = mouseX * 0.4 - width / 5
        fill(102); rect(xpos2, 0, thick, height / 2)
        fill(204); rect(xpos1, 0, thin, height / 2)
        fill(102); rect(xpos4, height / 2, thick, height / 2)
        fill(204); rect(xpos3, height / 2, thin, height / 2)
        xpos1 += mx / 16; xpos2 += mx / 64; xpos3 -= mx / 16; xpos4 -= mx / 64
        if xpos1 < -thin { xpos1 = width }; if xpos1 > width { xpos1 = -thin }
        if xpos2 < -thick { xpos2 = width }; if xpos2 > width { xpos2 = -thick }
        if xpos3 < -thin { xpos3 = width }; if xpos3 > width { xpos3 = -thin }
        if xpos4 < -thick { xpos4 = width }; if xpos4 > width { xpos4 = -thick }
    }
}
