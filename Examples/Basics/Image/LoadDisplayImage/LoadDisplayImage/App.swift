import metaphor
import Foundation

@main
final class LoadDisplayImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Load Display Image")
    }

    var img: MImage?

    func setup() {
        guard let path = Bundle.module.path(forResource: "moonwalk", ofType: "jpg", inDirectory: "Resources") else { return }
        img = try? loadImage(path)
    }

    func draw() {
        guard let img = img else { return }
        image(img, 0, 0)
        image(img, 0, height / 2, img.width / 2, img.height / 2)
    }
}
