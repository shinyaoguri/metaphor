import metaphor
import Foundation

@main
final class Threads: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Threads")
    }

    var finished = false
    var percent: Float = 0
    var wordCount = 0

    func setup() {
        // Spawn background task
        startLoading()
    }

    func draw() {
        background(0)

        if !finished {
            // Loading bar
            stroke(255)
            noFill()
            rect(width / 2 - 150, height / 2, 300, 10)
            fill(255)
            let w = map(percent, 0, 1, 0, 300)
            rect(width / 2 - 150, height / 2, w, 10)
            textSize(16)
            textAlign(.center)
            fill(255)
            text("Loading...", width / 2, height / 2 + 30)
        } else {
            textAlign(.center)
            textSize(18)
            fill(255)
            text("Finished processing \(wordCount) words.", width / 2, height / 2 - 10)
            textSize(14)
            fill(200)
            text("Click to load again.", width / 2, height / 2 + 20)
        }
    }

    func mousePressed() {
        if finished {
            startLoading()
        }
    }

    func startLoading() {
        finished = false
        percent = 0
        wordCount = 0

        // Simulate background data processing with Task
        Task.detached { [self] in
            let sampleTexts = [
                "The quick brown fox jumps over the lazy dog",
                "Swift is a powerful and intuitive programming language",
                "Creative coding bridges art and technology",
                "Processing inspired a generation of artists",
                "Metal provides low level GPU access on Apple platforms",
                "Generative art creates beauty from algorithms",
                "Real time graphics require efficient rendering",
                "Particle systems simulate natural phenomena",
                "Shaders enable per pixel computation on GPU",
                "Audio reactive visuals respond to sound input",
                "Physics engines model forces and collisions",
                "Vector math is fundamental to computer graphics",
                "The metaphor library brings Processing to Swift",
            ]

            var allWords: [String] = []

            for i in 0..<sampleTexts.count {
                // Simulate processing delay
                try? await Task.sleep(for: .milliseconds(150))

                let words = sampleTexts[i].split(separator: " ").map { String($0).lowercased() }
                allWords.append(contentsOf: words)
                allWords.sort()

                await MainActor.run {
                    self.percent = Float(i + 1) / Float(sampleTexts.count)
                }
            }

            await MainActor.run {
                self.wordCount = allWords.count
                self.finished = true
            }
        }
    }
}
