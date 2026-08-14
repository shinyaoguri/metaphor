import metaphor

@main
final class SaveOneImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SaveOneImage")
    }

    let outputPath = "output/line.png"

    func setup() {}

    func draw() {
        background(204)
        line(0, 0, mouseX, height)
        line(width, 0, 0, mouseY)
    }

    func mousePressed() {
        // The original saves "line.tif" next to the sketch. metaphor writes PNG,
        // and relative paths resolve from the directory the sketch was launched in
        // (the package root when started with `swift run`).
        // save() only reserves the write: the file is produced from the finished
        // frame, after draw() returns.
        save(outputPath)
        print("Saved \(outputPath)")
    }
}
