import metaphor

@main
final class Keyboard: Sketch {
    var rectW: Float = 0
    var config: SketchConfig { SketchConfig(title: "Keyboard", width: 640, height: 360) }
    func setup() {
        noStroke()
        background(0)
        rectW = width / 4
    }
    func draw() {}
    func keyPressed() {
        let k = key
        var keyIndex = -1
        if k >= "A" && k <= "Z" {
            keyIndex = Int(k.asciiValue! - Character("A").asciiValue!)
        } else if k >= "a" && k <= "z" {
            keyIndex = Int(k.asciiValue! - Character("a").asciiValue!)
        }
        if keyIndex == -1 {
            background(0)
        } else {
            fill(Float(Int(time * 1000) % 255))
            let x = map(Float(keyIndex), 0, 25, 0, width - rectW)
            rect(x, 0, rectW, height)
        }
    }
}
