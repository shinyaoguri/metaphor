import metaphor

@main
final class StoringInput: Sketch {
    let num = 60
    var mx: [Float] = []
    var my: [Float] = []
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Storing Input") }
    func setup() {
        noStroke()
        fill(255, 153)
        mx = [Float](repeating: 0, count: num)
        my = [Float](repeating: 0, count: num)
    }
    func draw() {
        background(51)
        let which = frameCount % num
        mx[which] = mouseX
        my[which] = mouseY
        for i in 0..<num {
            let index = (which + 1 + i) % num
            ellipse(mx[index], my[index], Float(i), Float(i))
        }
    }
}
