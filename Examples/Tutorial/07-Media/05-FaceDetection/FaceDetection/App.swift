import Vision
import metaphor

@main
final class FaceDetection: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Face Detection")
    }

    var capture: CaptureDevice?
    // Metal のテクスチャを Vision が読める形（CVPixelBuffer）へ渡すための変換器
    var converter: MLTextureConverter!

    // 直前の検出結果。Vision の座標系（左下原点・0...1 の正規化）のまま持つ
    var faces: [CGRect] = []

    func setup() {
        capture = createCapture(width: 1280, height: 720)
        converter = createMLTextureConverter()
    }

    func draw() {
        background(12)

        guard let capture, capture.isAvailable, let texture = capture.texture else {
            noStroke()
            fill(Color(gray: 0.6))
            textSize(16)
            textAlign(.center, .center)
            text("カメラの映像を待っています", width / 2, height / 2)
            return
        }

        image(capture, 0, 0, width, height)

        // カメラのフレームを Vision に渡して顔を探す
        if let pixelBuffer = converter.pixelBuffer(from: texture) {
            detect(in: pixelBuffer)
        }

        drawFaces()
    }

    /// 顔の矩形を求める。metaphor の外側（Apple の Vision）の仕事
    private func detect(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        faces = request.results?.map { $0.boundingBox } ?? []
    }

    /// 検出結果を画面の座標へ直して重ねる
    private func drawFaces() {
        noFill()
        stroke(Color(r: 0.3, g: 1, b: 0.5))
        strokeWeight(3)
        for face in faces {
            // Vision は左下原点。metaphor は左上原点なので y を反転する
            let x = Float(face.origin.x) * width
            let y = (1 - Float(face.origin.y + face.height)) * height
            rect(x, y, Float(face.width) * width, Float(face.height) * height)
        }

        noStroke()
        fill(Color(gray: 0.9))
        textSize(14)
        textAlign(.left, .top)
        text("検出: \(faces.count) 人", 16, 16)
    }
}
