import metaphor

@main
final class KeyboardFunctions: Sketch {
    let maxHeight: Float = 40
    let minHeight: Float = 20
    var letterHeight: Float = 40
    let letterWidth: Float = 20
    var x: Float = -20
    var y: Float = 0
    var newletter = false
    let numChars = 26
    var colors: [Color] = []
    var config: SketchConfig { SketchConfig(title: "Keyboard Functions", width: 640, height: 360) }
    func setup() {
        noStroke()
        colorMode(.hsb, Float(numChars), Float(numChars), Float(numChars))
        background(Float(numChars) / 2)
        for i in 0..<numChars {
            colors.append(Color(Float(i) / Float(numChars), 1.0, 1.0))
        }
    }
    func draw() {
        if newletter {
            if letterHeight == maxHeight {
                rect(x, y, letterWidth, letterHeight)
            } else {
                rect(x, y + minHeight, letterWidth, letterHeight)
                fill(Float(numChars) / 2)
                rect(x, y + minHeight - minHeight, letterWidth, letterHeight)
            }
            newletter = false
        }
    }
    func keyPressed() {
        let k = key
        if (k >= "A" && k <= "Z") || (k >= "a" && k <= "z") {
            var keyIndex: Int
            if k <= "Z" {
                keyIndex = Int(k.asciiValue! - Character("A").asciiValue!)
                letterHeight = maxHeight
            } else {
                keyIndex = Int(k.asciiValue! - Character("a").asciiValue!)
                letterHeight = minHeight
            }
            fill(colors[keyIndex])
        } else {
            fill(0)
            letterHeight = 10
        }
        newletter = true
        x += letterWidth
        if x > width - letterWidth {
            x = 0
            y += maxHeight
        }
        if y > height - letterHeight {
            y = 0
        }
    }
}
