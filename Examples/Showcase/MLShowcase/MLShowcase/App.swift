import metaphor
import Foundation

/// CoreML / Vision 統合機能のショーケース
///
/// 数字キー 1〜9 でシーンを切り替え:
///   1: 画像分類 (VNClassifyImageRequest)
///   2: 顔検出 + ランドマーク (VNDetectFaceLandmarksRequest)
///   3: ボディポーズ推定 (VNDetectHumanBodyPoseRequest)
///   4: ハンドポーズ推定 (VNDetectHumanHandPoseRequest)
///   5: テキスト認識 / OCR (VNRecognizeTextRequest)
///   6: 人物セグメンテーション (VNGeneratePersonSegmentationRequest)
///   7: サリエンシー検出 (VNGenerateAttentionBasedSaliencyImageRequest)
///   8: バーコード / QR 検出 (VNDetectBarcodesRequest)
///   9: 輪郭検出 (VNDetectContoursRequest)
///
/// その他の操作:
///   C: カメラ使用 / テスト画像 を切り替え
///   I: 推論時間の表示切替
@main
final class MLShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "CoreML / Vision Showcase",
            windowScale: 1.0
        )
    }

    // MARK: - State

    var currentScene: Int = 1
    var showInferenceTime = true
    var useCameraInput = false

    // ML instances
    var vision: MLVision!
    var cam: CaptureDevice?

    // Test image (generated procedurally)
    var testTexture: MTLTexture?

    // Scene names
    let sceneNames = [
        1: "Image Classification",
        2: "Face Detection + Landmarks",
        3: "Body Pose Estimation",
        4: "Hand Pose Estimation",
        5: "Text Recognition (OCR)",
        6: "Person Segmentation",
        7: "Saliency Detection",
        8: "Barcode / QR Detection",
        9: "Contour Detection",
    ]

    // MARK: - Lifecycle

    func setup() {
        vision = createVision()
        vision.maxClassifications = 10
        vision.confidenceThreshold = 0.3
        vision.textRecognitionLanguages = ["en", "ja"]

        generateTestTexture()
    }

    func draw() {
        background(Color(gray: 0.08))

        // Update results
        vision.update()
        if useCameraInput {
            cam?.read()
        }

        // Get input texture
        let inputTexture = currentInputTexture()

        // Draw input image (left side)
        drawInputPreview(inputTexture)

        // Run current scene's analysis
        if let tex = inputTexture {
            runAnalysis(tex)
        }

        // Draw results overlay
        drawResults(inputTexture)

        // Draw HUD
        drawHUD()
    }

    func keyPressed() {
        guard let k = key else { return }

        switch k {
        case "1": currentScene = 1
        case "2": currentScene = 2
        case "3": currentScene = 3
        case "4": currentScene = 4
        case "5": currentScene = 5
        case "6": currentScene = 6
        case "7": currentScene = 7
        case "8": currentScene = 8
        case "9": currentScene = 9
        case "c", "C":
            useCameraInput.toggle()
            if useCameraInput && cam == nil {
                cam = createCapture(width: 1280, height: 720)
            }
        case "i", "I":
            showInferenceTime.toggle()
        default: break
        }
    }

    // MARK: - Input

    func currentInputTexture() -> MTLTexture? {
        if useCameraInput, let camTex = cam?.texture {
            return camTex
        }
        return testTexture
    }

    // MARK: - Analysis Dispatch

    func runAnalysis(_ texture: MTLTexture) {
        guard !vision.isProcessing else { return }

        switch currentScene {
        case 1: vision.classify(texture)
        case 2: vision.detectFaces(texture)
        case 3: vision.detectPose(texture)
        case 4: vision.detectHandPose(texture)
        case 5: vision.recognizeText(texture)
        case 6: vision.segmentPerson(texture)
        case 7: vision.detectSaliency(texture, type: .attention)
        case 8: vision.detectBarcodes(texture)
        case 9: vision.detectContours(texture)
        default: break
        }
    }

    // MARK: - Drawing: Input Preview

    func drawInputPreview(_ texture: MTLTexture?) {
        guard let tex = texture else { return }

        let previewW: Float = 640
        let previewH: Float = 480
        let previewX: Float = 20
        let previewY: Float = 80

        // Draw border
        noFill()
        stroke(Color(gray: 0.3))
        strokeWeight(1)
        rect(previewX - 1, previewY - 1, previewW + 2, previewH + 2)

        // Draw image
        noStroke()
        let img = MImage(texture: tex)
        image(img, previewX, previewY, previewW, previewH)

        // Label
        fill(Color(gray: 0.5))
        textSize(12)
        text(useCameraInput ? "Input: Camera" : "Input: Test Image", previewX, previewY - 8)
    }

    // MARK: - Drawing: Results

    func drawResults(_ inputTexture: MTLTexture?) {
        let resultX: Float = 680
        let resultY: Float = 80
        let previewX: Float = 20
        let previewY: Float = 80
        let previewW: Float = 640
        let previewH: Float = 480

        fill(Color(gray: 0.6))
        textSize(14)
        text("Results:", resultX, resultY - 8)

        switch currentScene {
        case 1:
            drawClassificationResults(resultX, resultY)
        case 2:
            drawFaceOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawFaceResults(resultX, resultY)
        case 3:
            drawPoseOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawPoseResults(resultX, resultY)
        case 4:
            drawPoseOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawHandPoseResults(resultX, resultY)
        case 5:
            drawTextOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawTextResults(resultX, resultY)
        case 6:
            drawSegmentationResult(resultX, resultY)
        case 7:
            drawSaliencyResult(resultX, resultY)
        case 8:
            drawBarcodeOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawBarcodeResults(resultX, resultY)
        case 9:
            drawContourOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawContourResults(resultX, resultY)
        default: break
        }
    }

    // MARK: - Scene 1: Classification

    func drawClassificationResults(_ x: Float, _ y: Float) {
        let classifications = vision.classifications
        if classifications.isEmpty {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Analyzing...", x, y + 20)
            return
        }

        for (i, cls) in classifications.enumerated() {
            let yPos = y + Float(i) * 40 + 10

            // Confidence bar
            let barW: Float = 300
            let barH: Float = 20
            noStroke()
            fill(Color(gray: 0.15))
            rect(x, yPos, barW, barH)

            let hue = Float(i) / Float(classifications.count)
            fill(Color(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 0.8))
            rect(x, yPos, barW * cls.confidence, barH)

            // Label
            fill(.white)
            textSize(12)
            text("\(cls.label)", x + 4, yPos + 14)

            // Confidence percentage
            fill(Color(gray: 0.7))
            textSize(11)
            let pct = String(format: "%.1f%%", cls.confidence * 100)
            text(pct, x + barW + 10, yPos + 14)
        }
    }

    // MARK: - Scene 2: Face Detection

    func drawFaceOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for face in vision.faces {
            // Bounding box
            noFill()
            stroke(Color(hue: 0.33, saturation: 1, brightness: 1))
            strokeWeight(2)
            rect(
                px + face.x * scaleX,
                py + face.y * scaleY,
                face.w * scaleX,
                face.h * scaleY
            )

            // Landmarks
            for lm in face.landmarks {
                noStroke()
                fill(Color(hue: 0.15, saturation: 1, brightness: 1))
                circle(px + lm.x * scaleX, py + lm.y * scaleY, 6)

                fill(.white)
                textSize(9)
                text(lm.name, px + lm.x * scaleX + 5, py + lm.y * scaleY - 4)
            }
        }
    }

    func drawFaceResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Faces detected: \(vision.faces.count)", x, y + 20)

        for (i, face) in vision.faces.enumerated() {
            let yPos = y + Float(i) * 60 + 50
            fill(Color(gray: 0.7))
            textSize(12)
            text("Face \(i + 1):", x, yPos)
            text("  Position: (\(Int(face.x)), \(Int(face.y)))", x, yPos + 16)
            text("  Size: \(Int(face.w)) x \(Int(face.h))", x, yPos + 32)
            text("  Landmarks: \(face.landmarks.count)", x, yPos + 48)
        }
    }

    // MARK: - Scene 3: Body Pose

    func drawPoseOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for pose in vision.poses {
            // Draw joints
            for lm in pose.landmarks where lm.confidence > 0.3 {
                let cx = px + lm.x * scaleX
                let cy = py + lm.y * scaleY

                // Joint circle
                noStroke()
                let alpha = lm.confidence
                fill(Color(hue: 0.0, saturation: 1, brightness: 1, alpha: alpha))
                circle(cx, cy, 10)

                // Joint name (small)
                fill(Color(r: 1, g: 1, b: 1, a: alpha))
                textSize(8)
                text(String(lm.name.prefix(8)), cx + 7, cy - 2)
            }

            // Draw connections between nearby joints
            let highConfidence = pose.landmarks.filter { $0.confidence > 0.3 }
            noFill()
            stroke(Color(hue: 0.55, saturation: 0.8, brightness: 1, alpha: 0.5))
            strokeWeight(2)

            // Simple connections: draw lines between adjacent detected joints
            for i in 0..<highConfidence.count {
                for j in (i + 1)..<highConfidence.count {
                    let a = highConfidence[i]
                    let b = highConfidence[j]
                    let dist = sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
                    // Only connect joints within reasonable distance
                    if dist < Float(tex.width) * 0.15 {
                        line(
                            px + a.x * scaleX, py + a.y * scaleY,
                            px + b.x * scaleX, py + b.y * scaleY
                        )
                    }
                }
            }
        }
    }

    func drawPoseResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Bodies detected: \(vision.poses.count)", x, y + 20)

        for (i, pose) in vision.poses.enumerated() {
            let yPos = y + Float(i) * 40 + 50
            let highConf = pose.landmarks.filter { $0.confidence > 0.3 }
            fill(Color(gray: 0.7))
            textSize(12)
            text("Body \(i + 1): \(highConf.count) joints (conf: \(String(format: "%.0f%%", pose.confidence * 100)))", x, yPos)
        }
    }

    // MARK: - Scene 4: Hand Pose

    func drawHandPoseResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Hands detected: \(vision.poses.count)", x, y + 20)

        for (i, pose) in vision.poses.enumerated() {
            let yPos = y + Float(i) * 40 + 50
            let highConf = pose.landmarks.filter { $0.confidence > 0.3 }
            fill(Color(gray: 0.7))
            textSize(12)
            text("Hand \(i + 1): \(highConf.count) joints", x, yPos)
        }
    }

    // MARK: - Scene 5: Text Recognition

    func drawTextOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for t in vision.texts {
            // Bounding box
            noFill()
            stroke(Color(hue: 0.6, saturation: 1, brightness: 1))
            strokeWeight(1)
            rect(
                px + t.x * scaleX,
                py + t.y * scaleY,
                t.w * scaleX,
                t.h * scaleY
            )

            // Text label
            fill(Color(hue: 0.6, saturation: 0.5, brightness: 1))
            textSize(10)
            text(String(t.text.prefix(30)), px + t.x * scaleX, py + t.y * scaleY - 4)
        }
    }

    func drawTextResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Text regions: \(vision.texts.count)", x, y + 20)

        for (i, t) in vision.texts.prefix(10).enumerated() {
            let yPos = y + Float(i) * 30 + 50
            fill(Color(gray: 0.7))
            textSize(11)
            let conf = String(format: "%.0f%%", t.confidence * 100)
            text("[\(conf)] \(String(t.text.prefix(40)))", x, yPos)
        }
    }

    // MARK: - Scene 6: Person Segmentation

    func drawSegmentationResult(_ x: Float, _ y: Float) {
        // Draw mask texture if available
        if let maskTex = vision.segmentMaskTexture {
            let maskW: Float = 320
            let maskH: Float = 240

            // Draw mask preview
            fill(Color(gray: 0.5))
            textSize(12)
            text("Segmentation Mask:", x, y + 10)

            image(maskTex, x, y + 20, maskW, maskH)

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x - 1, y + 19, maskW + 2, maskH + 2)
        }

        if let mask = vision.segmentMask {
            fill(Color(gray: 0.7))
            textSize(12)
            let yOff: Float = vision.segmentMaskTexture != nil ? 290 : 20
            text("Mask size: \(mask.width) x \(mask.height)", x, y + yOff)
            text("Pixels: \(mask.data.count)", x, y + yOff + 18)

            // Histogram of mask values
            if !mask.data.isEmpty {
                let bins = 10
                var histogram = [Int](repeating: 0, count: bins)
                for v in mask.data {
                    let bin = min(bins - 1, Int(v * Float(bins)))
                    histogram[bin] += 1
                }
                let maxCount = histogram.max() ?? 1

                text("Value distribution:", x, y + yOff + 46)
                for i in 0..<bins {
                    let barX = x + Float(i) * 30
                    let barH = Float(histogram[i]) / Float(maxCount) * 60
                    noStroke()
                    fill(Color(gray: Float(i) / Float(bins)))
                    rect(barX, y + yOff + 120 - barH, 25, barH)
                }
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Analyzing...", x, y + 20)
        }
    }

    // MARK: - Scene 7: Saliency

    func drawSaliencyResult(_ x: Float, _ y: Float) {
        if let sal = vision.saliency {
            fill(Color(gray: 0.5))
            textSize(12)
            text("Saliency Heatmap (\(sal.width) x \(sal.height)):", x, y + 10)

            // Draw heatmap manually
            let cellW: Float = min(400 / Float(sal.width), 20)
            let cellH: Float = min(300 / Float(sal.height), 20)
            let drawW = cellW * Float(sal.width)
            let drawH = cellH * Float(sal.height)

            for sy in 0..<sal.height {
                for sx in 0..<sal.width {
                    let v = sal.data[sy * sal.width + sx]
                    noStroke()
                    // Hot colormap: black -> blue -> red -> yellow -> white
                    let r = min(1, v * 3)
                    let g = min(1, max(0, v * 3 - 1))
                    let b = min(1, max(0, (v - 0.33) * 3))
                    fill(Color(r: r, g: g, b: b))
                    rect(
                        x + Float(sx) * cellW,
                        y + 20 + Float(sy) * cellH,
                        cellW, cellH
                    )
                }
            }

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x - 1, y + 19, drawW + 2, drawH + 2)

            // Stats
            if !sal.data.isEmpty {
                let maxVal = sal.data.max() ?? 0
                let minVal = sal.data.min() ?? 0
                let avg = sal.data.reduce(0, +) / Float(sal.data.count)
                fill(Color(gray: 0.7))
                textSize(11)
                text("Min: \(String(format: "%.3f", minVal))  Max: \(String(format: "%.3f", maxVal))  Avg: \(String(format: "%.3f", avg))", x, y + drawH + 40)
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Analyzing...", x, y + 20)
        }
    }

    // MARK: - Scene 8: Barcode / QR

    func drawBarcodeOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for bc in vision.barcodes {
            // Bounding box
            noFill()
            stroke(Color(hue: 0.8, saturation: 1, brightness: 1))
            strokeWeight(2)
            rect(
                px + bc.x * scaleX,
                py + bc.y * scaleY,
                bc.w * scaleX,
                bc.h * scaleY
            )

            // Label
            fill(Color(hue: 0.8, saturation: 0.5, brightness: 1))
            textSize(10)
            text(bc.symbology, px + bc.x * scaleX, py + bc.y * scaleY - 4)
        }
    }

    func drawBarcodeResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Barcodes detected: \(vision.barcodes.count)", x, y + 20)

        for (i, bc) in vision.barcodes.enumerated() {
            let yPos = y + Float(i) * 50 + 50
            fill(Color(gray: 0.7))
            textSize(12)
            text("[\(bc.symbology)]", x, yPos)
            fill(.white)
            text(String(bc.payload.prefix(50)), x + 10, yPos + 18)
            fill(Color(gray: 0.5))
            textSize(10)
            text("Pos: (\(Int(bc.x)), \(Int(bc.y))) Size: \(Int(bc.w))x\(Int(bc.h))", x + 10, yPos + 34)
        }

        if vision.barcodes.isEmpty {
            fill(Color(gray: 0.4))
            textSize(14)
            text("No barcodes found (point camera at a QR code)", x, y + 20)
        }
    }

    // MARK: - Scene 9: Contour Detection

    func drawContourOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        noFill()
        strokeWeight(1.5)

        for (i, contour) in vision.contours.enumerated() {
            let hue = Float(i) / max(1, Float(vision.contours.count))
            stroke(Color(hue: hue, saturation: 1, brightness: 1, alpha: 0.8))

            guard contour.points.count > 1 else { continue }

            for j in 0..<(contour.points.count - 1) {
                let a = contour.points[j]
                let b = contour.points[j + 1]
                line(
                    px + a.x * scaleX, py + a.y * scaleY,
                    px + b.x * scaleX, py + b.y * scaleY
                )
            }
            // Close contour
            let first = contour.points[0]
            let last = contour.points[contour.points.count - 1]
            line(
                px + last.x * scaleX, py + last.y * scaleY,
                px + first.x * scaleX, py + first.y * scaleY
            )
        }
    }

    func drawContourResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Contours detected: \(vision.contours.count)", x, y + 20)

        for (i, contour) in vision.contours.prefix(15).enumerated() {
            let yPos = y + Float(i) * 20 + 50
            let hue = Float(i) / max(1, Float(vision.contours.count))
            fill(Color(hue: hue, saturation: 0.7, brightness: 1))
            textSize(11)
            text("Contour \(i + 1): \(contour.points.count) points, \(contour.childIndices.count) children", x, yPos)
        }
    }

    // MARK: - HUD

    func drawHUD() {
        // Title bar
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.7))
        rect(0, 0, width, 60)

        // Scene title
        fill(.white)
        textSize(22)
        let sceneName = sceneNames[currentScene] ?? "Unknown"
        text("Scene \(currentScene): \(sceneName)", 20, 38)

        // Controls
        fill(Color(gray: 0.5))
        textSize(11)
        text("[1-9] Switch Scene  [C] Toggle Camera  [I] Toggle Info", 20, height - 12)

        // Inference time
        if showInferenceTime && vision.inferenceTime > 0 {
            fill(Color(hue: 0.33, saturation: 0.8, brightness: 0.9))
            textSize(12)
            let ms = String(format: "%.1f ms", vision.inferenceTime * 1000)
            text("Inference: \(ms)", width - 160, 38)

            // Processing indicator
            if vision.isProcessing {
                fill(Color(hue: 0.1, saturation: 1, brightness: 1))
                circle(width - 175, 34, 8)
            } else {
                fill(Color(hue: 0.33, saturation: 1, brightness: 1))
                circle(width - 175, 34, 8)
            }
        }

        // Input source indicator
        fill(useCameraInput ? Color(hue: 0.33, saturation: 0.8, brightness: 0.9) : Color(gray: 0.5))
        textSize(11)
        text(useCameraInput ? "CAMERA" : "TEST IMAGE", width - 160, 16)
    }

    // MARK: - Test Image Generation

    func generateTestTexture() {
        // Create a procedural test image with shapes, text-like patterns, and edges
        // This gives Vision something to analyze even without a camera
        let w = 1280
        let h = 720
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif

        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = device.makeTexture(descriptor: desc) else { return }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        // Background gradient
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let gradV = UInt8(Float(y) / Float(h) * 80 + 40)
                let gradH = UInt8(Float(x) / Float(w) * 30)
                pixels[i] = gradV + gradH  // B
                pixels[i + 1] = gradV      // G
                pixels[i + 2] = gradV / 2  // R
                pixels[i + 3] = 255        // A
            }
        }

        // Draw some shapes for contour detection / classification
        // Circle (face-like)
        let cx = 400
        let cy = 300
        let radius = 120
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius) {
                let dx = x - cx
                let dy = y - cy
                if dx * dx + dy * dy <= radius * radius {
                    guard x >= 0, x < w, y >= 0, y < h else { continue }
                    let i = (y * w + x) * 4
                    pixels[i] = 180     // B
                    pixels[i + 1] = 200 // G
                    pixels[i + 2] = 220 // R
                    pixels[i + 3] = 255
                }
            }
        }

        // "Eyes" (two small dark circles)
        for eye in [(cx - 40, cy - 20), (cx + 40, cy - 20)] {
            let er = 15
            for y in (eye.1 - er)...(eye.1 + er) {
                for x in (eye.0 - er)...(eye.0 + er) {
                    let dx = x - eye.0
                    let dy = y - eye.1
                    if dx * dx + dy * dy <= er * er {
                        guard x >= 0, x < w, y >= 0, y < h else { continue }
                        let i = (y * w + x) * 4
                        pixels[i] = 30
                        pixels[i + 1] = 30
                        pixels[i + 2] = 40
                        pixels[i + 3] = 255
                    }
                }
            }
        }

        // Rectangle (for contour detection)
        for y in 150..<250 {
            for x in 800..<1000 {
                guard x < w, y < h else { continue }
                let i = (y * w + x) * 4
                pixels[i] = 50      // B
                pixels[i + 1] = 150 // G
                pixels[i + 2] = 255 // R
                pixels[i + 3] = 255
            }
        }

        // Triangle
        for y in 400..<600 {
            let triTop = 400
            let triBot = 600
            let triCx = 900
            let progress = Float(y - triTop) / Float(triBot - triTop)
            let halfWidth = Int(progress * 100)
            for x in (triCx - halfWidth)...(triCx + halfWidth) {
                guard x >= 0, x < w, y < h else { continue }
                let i = (y * w + x) * 4
                pixels[i] = 200     // B
                pixels[i + 1] = 100 // G
                pixels[i + 2] = 50  // R
                pixels[i + 3] = 255
            }
        }

        // High-contrast edges (for saliency)
        for y in 500..<520 {
            for x in 100..<600 {
                guard x < w, y < h else { continue }
                let i = (y * w + x) * 4
                pixels[i] = 255
                pixels[i + 1] = 255
                pixels[i + 2] = 255
                pixels[i + 3] = 255
            }
        }

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: w * 4
        )

        testTexture = tex
    }
}
