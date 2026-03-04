import metaphor

@main
final class SaveFile2: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "SaveFile2", width: 640, height: 360)
    }

    var positions: [(Int, Int)] = []

    func setup() {
        frameRate(12)
    }

    func draw() {
        if isMousePressed {
            point(mouseX, mouseY)
            positions.append((Int(mouseX), Int(mouseY)))
        }
    }

    func keyPressed() {
        // Print recorded positions (original saves to file)
        print("--- Recorded Positions ---")
        for (x, y) in positions {
            print("\(x)\t\(y)")
        }
        print("--- \(positions.count) points recorded ---")
        positions.removeAll()
    }
}
