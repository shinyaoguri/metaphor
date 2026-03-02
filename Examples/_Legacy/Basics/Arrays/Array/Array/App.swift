import metaphor

@main
final class Array: Sketch {
    let coswave: [Float]
    var config: SketchConfig {
        SketchConfig(title: "Array")
    }

    func setup() {
        createCanvas(width: 640, height: 360)
        coswave = new Array[width]
        for i in 0..<width {
            let amount: Float = map(Float(i), 0.0, Float(width), 0.0, .pi)
            coswave[i] = abs(cos(amount))
        }
        background(255)
        noLoop()
    }

    func draw() {
        var y1 = 0
        var y2 = height / 2
        for i in 0..<width {
            stroke(coswave[i] * 255)
            line(x1: i, y1: y1, x2: i, y2: y2)
        }
        y1 = y2
        y2 = y1 + y1
        for i in 0..<width {
            stroke(coswave[i] * 255 / 4)
            line(x1: i, y1: y1, x2: i, y2: y2)
        }
        y1 = y2
        y2 = height
        
    }
}