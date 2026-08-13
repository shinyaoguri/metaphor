import metaphor

@main
final class SaveFrames: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SaveFrames")
    }

    // Relative to the directory the sketch was launched in
    // (the package root when started with `swift run`). Created if missing.
    let outputDirectory = "output/frames"

    var recording = false
    var savedCount = 0

    func setup() {}

    func draw() {
        background(0)

        // Oscillating rotating lines animation
        var a: Float = 0
        while a < TWO_PI {
            pushMatrix()
            translate(width / 2, height / 2)
            rotate(a + sin(Float(frameCount) * 0.004 * a))
            stroke(255)
            line(-100, 0, 100, 0)
            popMatrix()
            a += 0.2
        }

        // beginFrameRecord() keeps writing one PNG per frame until endFrameRecord(),
        // so there is no per-frame call here. Unlike the original, which called
        // saveFrame() before drawing the overlay, metaphor exports the finished
        // frame -- the status text and the red dot below end up in the files too.
        if recording {
            savedCount += 1
        }

        // Status text
        textAlign(.center)
        fill(255)
        textSize(14)
        if !recording {
            text("Press r to start recording.", width / 2, height - 24)
        } else {
            text("Recording frame \(savedCount)... Press r to stop.", width / 2, height - 24)
        }

        // Recording indicator dot
        stroke(255)
        if recording {
            fill(255, 0, 0)
        } else {
            noFill()
        }
        ellipse(width / 2, height - 48, 16, 16)
    }

    func keyPressed() {
        if key == "r" || key == "R" {
            recording = !recording
            if recording {
                savedCount = 0
                // The original numbered files with "frames####.png";
                // metaphor takes a printf-style pattern instead.
                beginFrameRecord(directory: outputDirectory, pattern: "frames%04d.png")
                print("Recording started -> \(outputDirectory)")
            } else {
                endFrameRecord()
                print("Recording stopped. \(savedCount) frames written to \(outputDirectory).")
            }
        }
    }
}
