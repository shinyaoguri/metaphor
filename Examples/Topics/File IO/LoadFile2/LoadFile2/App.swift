import metaphor

// NOTE: This example requires VLW font format (createFont with VLW file)
// which is not available in metaphor.
// Original Processing source: LoadFile2.pde

@main
final class LoadFile2: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadFile2 (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires VLW font format support\n(createFont with VLW file)\nnot available in metaphor", width / 2, height / 2)
    }
}
