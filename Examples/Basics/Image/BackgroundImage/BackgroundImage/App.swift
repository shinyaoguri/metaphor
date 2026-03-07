import metaphor
import Foundation

@main
final class BackgroundImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Background Image")
    }

    var bg: MImage?
    var y: Float = 0

    func setup() {
        guard let path = Bundle.module.path(forResource: "moonwalk", ofType: "jpg", inDirectory: "Resources") else { return }
        bg = try? loadImage(path)
    }

    func draw() {
        guard let bg = bg else { return }
        image(bg, 0, 0)

        stroke(226, 204, 0)
        line(0, y, width, y)

        y += 1
        if y > height {
            y = 0
        }
    }
}
