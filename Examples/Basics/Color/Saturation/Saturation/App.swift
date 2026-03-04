import metaphor

@main
final class Saturation: Sketch {
    var barWidth: Float = 20
    var lastBar: Int = -1
    var config: SketchConfig { SketchConfig(title: "Saturation", width: 640, height: 360) }
    func setup() {
        colorMode(.hsb, width, height, 100)
        noStroke()
    }
    func draw() {
        let whichBar = Int(mouseX / barWidth)
        if whichBar != lastBar {
            let barX = Float(whichBar) * barWidth
            fill(barX, mouseY, 66)
            rect(barX, 0, barWidth, height)
            lastBar = whichBar
        }
    }
}
