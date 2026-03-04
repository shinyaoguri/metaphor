import metaphor

@main
final class CountingStrings: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "CountingStrings", width: 640, height: 360)
    }

    var concordance: [String: Int] = [:]
    var tokens: [String] = []
    var counter = 0

    func setup() {
        // Generate sample text since we can't load files
        let sampleText = """
        the castle was dark and the wind was cold the count stood by the window
        looking out at the dark night the wolves were howling in the dark forest
        the castle was old and the walls were thick the count walked through the
        long dark corridor the candles flickered in the wind the shadows danced
        on the walls the count opened the heavy door the room was cold and dark
        the fire had gone out long ago the count sat in his chair by the window
        the moon was full and the light came through the glass the count watched
        the dark forest below the wolves howled again the wind blew through the
        castle the candles went out the darkness was complete the count smiled
        in the dark his eyes gleamed red in the moonlight the night was young
        and the hunt would begin soon the count rose from his chair and walked
        to the door the castle was silent the servants had all gone to sleep
        the count descended the stairs into the great hall the door creaked open
        and the cold night air rushed in the count stepped out into the darkness
        the wolves gathered around him the moon shone bright on the dark forest
        the count walked into the night his cape billowing in the cold wind
        """

        let lower = sampleText.lowercased()
        let cleaned = lower.replacingOccurrences(of: "\n", with: " ")
        tokens = cleaned.split(separator: " ").map { String($0) }
    }

    func draw() {
        background(51)
        fill(255)

        if counter < tokens.count {
            let s = tokens[counter]
            counter += 1
            concordance[s, default: 0] += 1
        }

        var x: Float = 0
        var y: Float = 48

        let sorted = concordance.sorted { $0.value > $1.value }

        for (word, count) in sorted {
            if count > 3 {
                let fsize = Float(min(max(count, 0), 48))
                textSize(fsize)
                text(word, x, y)
                x += Float(word.count) * fsize * 0.6 + fsize * 0.3
            }

            if x > width {
                x = 0
                y += 48
                if y > height { break }
            }
        }
    }
}
