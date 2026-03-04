import metaphor

@main
final class Letters: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Letters") }
    func setup() {
        background(0)
        textFont("Menlo")
        textAlign(.center, .center)
    }
    func draw() {
        background(0)
        let margin: Float = 10
        translate(margin * 4, margin * 4)
        let gap: Float = 46
        var counter = 35
        var y: Float = 0
        while y < height - gap {
            var x: Float = 0
            while x < width - gap {
                let letter = Character(UnicodeScalar(counter)!)
                if letter == "A" || letter == "E" || letter == "I" || letter == "O" || letter == "U" {
                    fill(255, 204, 0)
                } else {
                    fill(255)
                }
                textSize(24)
                text(String(letter), x, y)
                counter += 1
                x += gap
            }
            y += gap
        }
    }
}
