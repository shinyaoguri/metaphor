import metaphor

@main
final class CharactersStrings: Sketch {
    var letter: Character = " "
    var words: String = "Begin..."

    var config: SketchConfig { SketchConfig(title: "Characters Strings", width: 640, height: 360) }

    func setup() {
        textFont("Menlo")
    }

    func draw() {
        background(0)
        textSize(14)
        text("Click on the program, then type to add to the String", 50, 50)
        text("Current key: \(letter)", 50, 70)
        text("The String is \(words.count) characters long", 50, 90)
        textSize(36)
        text(words, 50, 120, 540, 300)
    }

    func keyPressed() {
        let c = key
        if (c >= "A" && c <= "z") || c == " " {
            letter = c
            words += String(c)
        }
    }
}
