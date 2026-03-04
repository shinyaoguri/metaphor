import metaphor

@main
final class Graphing2DEquation: Sketch {
    var config: SketchConfig { SketchConfig(title: "Graphing 2D Equation", width: 640, height: 360) }
    func draw() {
        let n = (mouseX * 10) / width
        let w: Float = 16; let h: Float = 16
        let dxVal = w / width; let dyVal = h / height
        var xCoord = -w / 2
        for i in 0..<Int(width) {
            var yCoord = -h / 2
            for j in 0..<Int(height) {
                let r = sqrt(xCoord * xCoord + yCoord * yCoord)
                let theta = atan2(yCoord, xCoord)
                let val = sin(n * cos(r) + 5 * theta)
                let gray = (val + 1.0) * 255.0 / 2.0
                stroke(gray)
                point(Float(i), Float(j))
                yCoord += dyVal
            }
            xCoord += dxVal
        }
    }
}
