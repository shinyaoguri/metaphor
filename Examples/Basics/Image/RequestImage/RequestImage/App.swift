import metaphor

@main
final class RequestImage: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Request Image", width: 640, height: 360)
    }

    var images: [MImage] = []

    func setup() {
        // Generate 12 sample images (replaces requestImage() calls)
        for i in 0..<12 {
            guard let img = createImage(160, 120) else { continue }
            img.loadPixels()
            let hue = Float(i) / 12.0
            for y in 0..<Int(img.height) {
                for x in 0..<Int(img.width) {
                    let idx = (y * Int(img.width) + x) * 4
                    let r = sin(hue * Float.pi * 2) * 127 + 128
                    let g = sin(hue * Float.pi * 2 + 2.094) * 127 + 128
                    let b = sin(hue * Float.pi * 2 + 4.189) * 127 + 128
                    let brightness = Float(x + y) / (img.width + img.height)
                    img.pixels[idx] = UInt8(r * brightness)
                    img.pixels[idx + 1] = UInt8(g * brightness)
                    img.pixels[idx + 2] = UInt8(b * brightness)
                    img.pixels[idx + 3] = 255
                }
            }
            img.updatePixels()
            images.append(img)
        }
        noLoop()
    }

    func draw() {
        background(0)
        let cols = 4
        for (i, img) in images.enumerated() {
            let col = i % cols
            let row = i / cols
            let x = Float(col) * img.width
            let y = Float(row) * img.height
            image(img, x, y)
        }
    }
}
