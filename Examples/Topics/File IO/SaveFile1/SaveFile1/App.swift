import metaphor

@main
final class SaveFile1: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SaveFile1")
    }

    var xPoints: [Float] = []
    var yPoints: [Float] = []

    func setup() {}

    func draw() {
        background(204)
        stroke(0)
        noFill()
        beginShape()
        for i in 0..<xPoints.count {
            vertex(xPoints[i], yPoints[i])
        }
        endShape()

        // Show the next segment to be added
        if xPoints.count >= 1 {
            stroke(255)
            line(mouseX, mouseY, xPoints[xPoints.count - 1], yPoints[yPoints.count - 1])
        }
    }

    func mousePressed() {
        xPoints.append(mouseX)
        yPoints.append(mouseY)
    }

    func keyPressed() {
        // Print data to console (original saves to file)
        print("--- Saved Line Data ---")
        for i in 0..<xPoints.count {
            print("\(Int(xPoints[i]))\t\(Int(yPoints[i]))")
        }
        print("--- End ---")
    }
}
