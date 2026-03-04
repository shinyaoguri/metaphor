import metaphor

@main
final class PieChart: Sketch {
    let angles: [Float] = [30, 10, 45, 35, 60, 38, 75, 67]
    var config: SketchConfig { SketchConfig(title: "Pie Chart", width: 640, height: 360) }
    func setup() {
        noStroke()
        noLoop()
    }
    func draw() {
        background(100)
        pieChart(300, angles)
    }
    private func pieChart(_ diameter: Float, _ data: [Float]) {
        var lastAngle: Float = 0
        for i in 0..<data.count {
            let gray = map(Float(i), 0, Float(data.count), 0, 255)
            fill(gray)
            arc(width / 2, height / 2, diameter, diameter, lastAngle, lastAngle + radians(data[i]))
            lastAngle += radians(data[i])
        }
    }
}
