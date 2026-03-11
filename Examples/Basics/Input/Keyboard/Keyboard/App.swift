import metaphor

@main
final class Keyboard: Sketch {
    var rectW: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Keyboard") }

    // Accumulated rectangles: (x position, fill grayscale)
    var rects: [(x: Float, gray: Float)] = []

    func setup() {
        noStroke()
        rectW = width / 4
    }

    func draw() {
        background(0)
        for r in rects {
            fill(r.gray)
            rect(r.x, 0, rectW, height)
        }
    }

    func keyPressed() {
        guard let k = key else { return }
        var keyIndex = -1
        if k >= "A" && k <= "Z" {
            keyIndex = Int(k.asciiValue! - Character("A").asciiValue!)
        } else if k >= "a" && k <= "z" {
            keyIndex = Int(k.asciiValue! - Character("a").asciiValue!)
        }
        if keyIndex == -1 {
            rects.removeAll()
        } else {
            let gray = Float(Int(time * 1000) % 255)
            let x = map(Float(keyIndex), 0, 25, 0, width - rectW)
            rects.append((x: x, gray: gray))
        }
    }
}
