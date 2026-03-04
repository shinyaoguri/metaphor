import metaphor

struct WordItem {
    var word: String
    var countBook1: Int = 0
    var countBook2: Int = 0
    var totalCount: Int = 0
    var posX: Float
    var posY: Float

    init(word: String, width: Float, height: Float) {
        self.word = word
        self.posX = Float.random(in: 0..<width)
        self.posY = Float.random(in: -height..<height * 2)
    }

    var qualifies: Bool {
        (countBook1 == totalCount || countBook2 == totalCount) && totalCount > 5
    }

    mutating func incrementBook1() { countBook1 += 1; totalCount += 1 }
    mutating func incrementBook2() { countBook2 += 1; totalCount += 1 }

    mutating func move(height: Float) {
        let speed = min(max(Float(totalCount - 5) / 20.0 * 0.3 + 0.1, 0), 10)
        posY += speed
        if posY > height * 2 { posY = -height }
    }
}

@main
final class HashMapClass: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "HashMapClass")
    }

    var words: [String: WordItem] = [:]

    func setup() {
        // Simulated book texts
        let book1 = "the castle was dark the count stood by the window the wolves howled in the dark forest the blood ran cold through the veins the castle walls were ancient the night was eternal the count descended the stairs the darkness surrounded him the fangs gleamed in the moonlight the coffin lay open the castle echoed with silence the count hungered the blood the castle the darkness the night the wolves the count the fangs the coffin the blood the darkness the castle the count"

        let book2 = "the laboratory was cold the scientist worked through the night the creature lay on the table the lightning struck the tower the creature opened its eyes the scientist screamed the monster rose from the table the storm raged outside the laboratory the creature walked the scientist fled the monster roamed the village the lightning the storm the creature the scientist the laboratory the monster the lightning the creature the storm the laboratory the scientist the monster the village the creature"

        loadText(book1, isBook1: true)
        loadText(book2, isBook1: false)
    }

    func loadText(_ text: String, isBook1: Bool) {
        let tokens = text.lowercased().split(separator: " ").map { String($0) }
        for s in tokens {
            if words[s] == nil {
                words[s] = WordItem(word: s, width: width, height: height)
            }
            if isBook1 {
                words[s]!.incrementBook1()
            } else {
                words[s]!.incrementBook2()
            }
        }
    }

    func draw() {
        background(126)

        for key in words.keys {
            guard words[key]!.qualifies else { continue }

            let w = words[key]!
            if w.countBook1 > 0 {
                fill(255)
            } else {
                fill(0)
            }

            let fs = min(max(Float(w.totalCount - 5) / 20.0 * 22.0 + 2.0, 2), 48)
            textSize(fs)
            textAlign(.center)
            text(w.word, w.posX, w.posY)

            words[key]!.move(height: height)
        }
    }
}
