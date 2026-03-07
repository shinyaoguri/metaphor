import metaphor
import Foundation

@main
final class RequestImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Request Image")
    }

    let imgCount = 12
    var imgs: [MImage] = []
    var loadStates: [Bool] = []
    var loaderX: Float = 0
    var loaderY: Float = 0
    var theta: Float = 0

    func setup() {
        loadStates = [Bool](repeating: false, count: imgCount)
        for i in 0..<imgCount {
            let name = String(format: "PT_anim%04d", i)
            guard let path = Bundle.module.path(forResource: name, ofType: "gif", inDirectory: "Resources"),
                  let img = try? loadImage(path) else { continue }
            imgs.append(img)
        }
    }

    func draw() {
        background(0)

        // Check load states
        for i in 0..<imgs.count {
            if imgs[i].width != 0 {
                loadStates[i] = true
            }
        }

        if checkLoadStates() {
            drawImages()
        } else {
            // Loading animation
            fill(255)
            noStroke()
            ellipse(loaderX, loaderY, 10, 10)
            loaderX += 2
            loaderY = height / 2 + sin(theta) * (height / 8)
            theta += Float.pi / 22
            if loaderX > width + 5 {
                loaderX = -5
            }
        }
    }

    private func drawImages() {
        guard !imgs.isEmpty else { return }
        let y = (height - imgs[0].height) / 2
        let imgW = width / Float(imgs.count)
        for (i, img) in imgs.enumerated() {
            image(img, imgW * Float(i), y, img.height, img.height)
        }
    }

    private func checkLoadStates() -> Bool {
        guard loadStates.count == imgCount else { return false }
        return !loadStates.contains(false)
    }
}
