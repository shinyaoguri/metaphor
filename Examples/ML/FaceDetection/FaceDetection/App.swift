// FaceDetection
//
// カメラ映像に対して VNDetectFaceRectanglesRequest を実行し、
// 検出された顔に矩形を描画するサンプル。
// CaptureDevice → MLTextureConverter → Vision の連携を示す。

import metaphor
import Vision

@main
final class FaceDetection: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "Face Detection")
    }

    var capture: CaptureDevice?
    var converter: MLTextureConverter!
    var faceRects: [CGRect] = []

    func setup() {
        capture = createCapture(width: 1280, height: 720, position: .front)
        converter = createMLTextureConverter()
    }

    func draw() {
        background(.black)

        guard let cam = capture else {
            fill(.white)
            textSize(20)
            text("Camera not available", 50, height / 2)
            return
        }

        // カメラ映像を表示
        image(cam, 0, 0, width, height)

        // カメラテクスチャ → CVPixelBuffer → Vision
        if let texture = cam.texture,
           let pixelBuffer = converter.pixelBuffer(from: texture) {
            detect(pixelBuffer: pixelBuffer)
        }

        // 検出結果を描画
        noFill()
        stroke(Color(r: 0, g: 1, b: 0))
        strokeWeight(3)
        for rect in faceRects {
            // Vision の座標系（左下原点・正規化）→ 画面座標に変換
            let x = Float(rect.origin.x) * width
            let y = (1 - Float(rect.origin.y + rect.height)) * height
            let w = Float(rect.width) * width
            let h = Float(rect.height) * height
            self.rect(x, y, w, h)
        }

        fill(.white)
        noStroke()
        textSize(16)
        text("Faces: \(faceRects.count)", 20, 30)
    }

    func detect(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        faceRects = request.results?.map { $0.boundingBox } ?? []
    }
}
