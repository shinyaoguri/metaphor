import metaphor

@main
final class LoadFile1: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "LoadFile1", width: 640, height: 360)
    }

    var lines: [(Float, Float)] = []
    var index = 0

    func setup() {
        background(0)
        stroke(255)
        frameRate(12)

        // Generate sample data (simulating loaded file)
        // Original would load "positions.txt" with tab-separated x,y pairs (0-100 range)
        for _ in 0..<200 {
            let x = Float.random(in: 0...100)
            let y = Float.random(in: 0...100)
            lines.append((x, y))
        }
    }

    func draw() {
        if index < lines.count {
            let (rawX, rawY) = lines[index]
            let x = map(rawX, 0, 100, 0, width)
            let y = map(rawY, 0, 100, 0, height)
            point(x, y)
            index += 1
        }
    }
}
