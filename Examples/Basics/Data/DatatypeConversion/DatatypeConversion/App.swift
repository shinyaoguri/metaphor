import metaphor

@main
final class DatatypeConversion: Sketch {
    var config: SketchConfig { SketchConfig(title: "Datatype Conversion", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        background(0)
        noStroke()
        textFont("Menlo")
        textSize(24)

        let c: Character = "A"
        let f: Float = Float(c.asciiValue ?? 0)  // 65.0
        let i: Int = Int(f * 1.4)                // 91
        let b: Int = Int(c.asciiValue ?? 0) / 2  // 32

        fill(255)
        text("The value of variable c is \(c)", 50, 100)
        text("The value of variable f is \(f)", 50, 150)
        text("The value of variable i is \(i)", 50, 200)
        text("The value of variable b is \(b)", 50, 250)
    }
}
