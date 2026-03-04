import metaphor

@main
final class Hue: Sketch {
    var barWidth: Float = 20
    var lastBar: Int = -1
    var config: SketchConfig { SketchConfig(title: "Hue", width: 640, height: 360) }
    func setup() {
        colorMode(.hsb, height, height, height)
        noStroke()
        background(0)
    }
    func draw() {
        let whichBar = Int(mouseX / barWidth)
        if whichBar != lastBar {
            let barX = Float(whichBar) * barWidth
            fill(mouseY, height, height)
            rect(barX, 0, barWidth, height)
            lastBar = whichBar
        }
    }
}
