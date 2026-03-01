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
        
    }
}