import Foundation
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

    /// 原典 `splitTokens(allText, " ,.?!:;[]-\"'")` と同じ区切り。
    let delimiters = CharacterSet(charactersIn: " ,.?!:;[]-\"'").union(.whitespacesAndNewlines)

    func setup() {
        loadBook("dracula", isBook1: true)
        loadBook("frankenstein", isBook1: false)
    }

    func loadBook(_ name: String, isBook1: Bool) {
        guard
            let path = Bundle.module.path(forResource: name, ofType: "txt", inDirectory: "Resources"),
            let lines = try? loadStrings(path)
        else { return }
        loadText(lines.joined(separator: " "), isBook1: isBook1)
    }

    func loadText(_ text: String, isBook1: Bool) {
        let tokens = text.lowercased()
            .components(separatedBy: delimiters)
            .filter { !$0.isEmpty }
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
