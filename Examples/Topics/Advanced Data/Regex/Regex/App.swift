import metaphor
import Foundation

// Processing original: https://github.com/processing/processing-examples/tree/main/Topics/Advanced%20Data/Regex
// The original .pde is not bundled — see Examples/NOTICE.md.

@main
final class Regex: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Regex")
    }

    var links: [String] = []

    func setup() {
        // Sample HTML since we can't load from URL
        let html = """
        <html><head><title>Sample</title></head><body>
        <a href="https://processing.org">Processing</a>
        <a href="https://p5js.org">p5.js</a>
        <a href="https://openframeworks.cc">openFrameworks</a>
        <a href="https://github.com/nicklama/metaphor">metaphor</a>
        <a href="https://developer.apple.com/metal/">Metal</a>
        <a href="https://swift.org">Swift</a>
        <a href="https://developer.apple.com/xcode/">Xcode</a>
        <a href="https://en.wikipedia.org/wiki/Creative_coding">Creative Coding</a>
        <a href="https://thecodingtrain.com">The Coding Train</a>
        <a href="https://natureofcode.com">Nature of Code</a>
        </body></html>
        """

        links = extractLinks(from: html)
    }

    func extractLinks(from html: String) -> [String] {
        var results: [String] = []
        let pattern = "<\\s*a\\s+href\\s*=\\s*\"(.*?)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            if match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: html) {
                results.append(String(html[r]))
            }
        }
        return results
    }

    func draw() {
        background(0)
        fill(255)
        textSize(14)
        for i in 0..<links.count {
            text(links[i], 10, 16 + Float(i) * 20)
        }
    }
}
