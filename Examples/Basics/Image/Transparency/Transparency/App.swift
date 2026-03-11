import metaphor
import Foundation

@main
final class Transparency: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Transparency")
    }

    var img: MImage?
    var offset: Float = 0
    let easing: Float = 0.05

    func setup() {
        guard let path = Bundle.module.path(forResource: "moonwalk", ofType: "jpg", inDirectory: "Resources"),
              let loaded = try? loadImage(path) else { return }
        img = loaded
    }

    func draw() {
        guard let img = img else { return }
        image(img, 0, 0) // Display at full opacity
        let dx = (mouseX - img.width / 2) - offset
        offset += dx * easing
        tint(255, 127) // Display at half opacity
        image(img, offset, 0)
    }
}
