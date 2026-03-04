import metaphor

@main
final class Relativity: Sketch {
    var a = Color(r: 165.0/255, g: 167.0/255, b: 20.0/255)
    var b = Color(r: 77.0/255, g: 86.0/255, b: 59.0/255)
    var c = Color(r: 42.0/255, g: 106.0/255, b: 105.0/255)
    var d = Color(r: 165.0/255, g: 89.0/255, b: 20.0/255)
    var e = Color(r: 146.0/255, g: 150.0/255, b: 127.0/255)
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Relativity") }
    func setup() {
        noStroke()
        noLoop()
    }
    func draw() {
        drawBand([a, b, c, d, e], 0, Int(width) / 128)
        drawBand([c, a, d, b, e], Int(height / 2), Int(width) / 128)
    }
    private func drawBand(_ colorOrder: [Color], _ ypos: Int, _ barWidth: Int) {
        let num = 5
        var i = 0
        while i < Int(width) {
            for j in 0..<num {
                fill(colorOrder[j])
                rect(Float(i + j * barWidth), Float(ypos), Float(barWidth), height / 2)
            }
            i += barWidth * num
        }
    }
}
