import metaphor

@main
final class Brightness: Sketch {
    var barWidth: Float = 20
    var lastBar: Int = -1
    var config: SketchConfig { SketchConfig(title: "Brightness", width: 640, height: 360) }
    func setup() {
        colorMode(.hsb, width, 100, height)
        noStroke()
        background(0)
    }
    func draw() {
        let whichBar = Int(mouseX / barWidth)
        if whichBar != lastBar {
            let barX = Float(whichBar) * barWidth
            fill(barX, 100, mouseY)
            rect(barX, 0, barWidth, height)
            lastBar = whichBar
        }
    }
}
