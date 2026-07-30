import metaphor

// Drop Image
// ウィンドウへ画像ファイルをドラッグ＆ドロップして表示する例。
// クリックすると selectInput() のファイルダイアログからも開ける。

@main
final class DropImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "DropImage")
    }

    var img: MImage?

    func draw() {
        background(51)
        if let img {
            // アスペクト比を保って中央に表示
            let scale = min(width / img.width, height / img.height, 1)
            let w = img.width * scale
            let h = img.height * scale
            image(img, (width - w) / 2, (height - h) / 2, w, h)
        } else {
            fill(255)
            textAlign(.center, .center)
            textSize(14)
            text("Drop an image file here\nor click to open a file dialog", width / 2, height / 2)
        }
    }

    func fileDropped(_ paths: [String]) {
        guard let path = paths.first else { return }
        img = try? loadImage(path)
    }

    func mousePressed() {
        selectInput("Select an image") { [weak self] path in
            guard let self, let path else { return }
            self.img = try? self.loadImage(path)
        }
    }
}
