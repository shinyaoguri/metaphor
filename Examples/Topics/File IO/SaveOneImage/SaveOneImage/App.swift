import metaphor

@main
final class SaveOneImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SaveOneImage")
    }

    func setup() {}

    func draw() {
        background(204)
        line(0, 0, mouseX, height)
        line(width, 0, 0, mouseY)
    }

    func mousePressed() {
        // Original calls save("line.tif")
        print("Image would be saved here (save() not available in metaphor)")
    }
}
