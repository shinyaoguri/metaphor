import metaphor

@main
final class Array: Sketch {
    var coswave: [Float] = []
    var config: SketchConfig { SketchConfig(title: "Array", width: 640, height: 360) }
    func setup() {
        coswave = (0..<Int(width)).map { i in
            abs(cos(map(Float(i), 0, width, 0, Float.pi)))
        }
        background(255)
        noLoop()
    }
    func draw() {
        let y1: Float = 0; let y2 = height / 3
        for i in 0..<Int(width) {
            stroke(coswave[i] * 255); line(Float(i), y1, Float(i), y2)
        }
        let y3 = y2; let y4 = y3 + y3
        for i in 0..<Int(width) {
            stroke(coswave[i] * 255 / 4); line(Float(i), y3, Float(i), y4)
        }
        let y5 = y4; let y6 = height
        for i in 0..<Int(width) {
            stroke(255 - coswave[i] * 255); line(Float(i), y5, Float(i), y6)
        }
    }
}
