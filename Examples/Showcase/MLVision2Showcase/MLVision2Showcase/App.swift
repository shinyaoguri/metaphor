import metaphor
import Foundation
import simd

/// Vision 拡張機能ショーケース（新規10機能）
///
/// 数字キー 1〜0 でシーンを切り替え:
///   1: 3D ボディポーズ推定 (VNDetectHumanBodyPose3DRequest)
///   2: 動物認識 (VNRecognizeAnimalsRequest)
///   3: 動物ポーズ推定 (VNDetectAnimalBodyPoseRequest)
///   4: 人物矩形検出 (VNDetectHumanRectanglesRequest)
///   5: 矩形検出 (VNDetectRectanglesRequest)
///   6: 画像特徴量 (VNGenerateImageFeaturePrintRequest)
///   7: 前景インスタンスマスク (VNGenerateForegroundInstanceMaskRequest)
///   8: 人物インスタンスマスク (VNGeneratePersonInstanceMaskRequest)
///   9: オブジェクトトラッキング (VNTrackObjectRequest)
///   0: オプティカルフロー (VNGenerateOpticalFlowRequest)
///
/// その他の操作:
///   C: カメラ / テスト画像 を切り替え
///   I: 推論時間の表示切替
///   T: トラッキング開始（シーン9 のみ、画面中央の物体を追跡）
///   R: トラッキング / オプティカルフロー リセット
@main
final class MLVision2Showcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1280,
            height: 720,
            title: "Vision Extended Showcase (10 Features)",
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

    // Test textures
    var testTexture: MTLTexture?
    var testTextureB: MTLTexture?  // 2nd image for feature print comparison

    // Feature print comparison
    var featurePrintA: MLFeaturePrint?
    var featurePrintB: MLFeaturePrint?
    var comparingSecond = false
    var featureDistance: Float?

    // Animated test texture for optical flow
    var flowFrameCount: Int = 0

    // Scene names
    let sceneNames: [Int: String] = [
        1: "3D Body Pose",
        2: "Animal Recognition",
        3: "Animal Pose",
        4: "Human Rectangles",
        5: "Rectangle Detection",
        6: "Image Feature Print",
        7: "Foreground Instance Mask",
        8: "Person Instance Mask",
        9: "Object Tracking",
        0: "Optical Flow",
    ]

    // MARK: - Lifecycle

    func setup() {
        vision = createVision()
        vision.confidenceThreshold = 0.3
        vision.maxRectangles = 10
        vision.rectangleMinSize = 0.05

        generateTestTexture()
        generateTestTextureB()
    }

    func draw() {
        background(Color(gray: 0.08))

        vision.update()
        if useCameraInput {
            cam?.read()
        }

        let inputTexture = currentInputTexture()

        // Draw input image (left side)
        drawInputPreview(inputTexture)

        // Run current scene's analysis
        if let tex = inputTexture {
            runAnalysis(tex)
        }

        // Draw results
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
        case "6":
            currentScene = 6
            featurePrintA = nil
            featurePrintB = nil
            featureDistance = nil
            comparingSecond = false
        case "7": currentScene = 7
        case "8": currentScene = 8
        case "9": currentScene = 9
        case "0": currentScene = 0
        case "c", "C":
            useCameraInput.toggle()
            if useCameraInput && cam == nil {
                cam = createCapture(width: 1280, height: 720)
            }
        case "i", "I":
            showInferenceTime.toggle()
        case "t", "T":
            if currentScene == 9 {
                // Start tracking from center of image
                let imgW: Float = 1280
                let imgH: Float = 720
                let trackW: Float = 200
                let trackH: Float = 200
                vision.startTracking(
                    x: (imgW - trackW) / 2,
                    y: (imgH - trackH) / 2,
                    w: trackW,
                    h: trackH,
                    imageWidth: imgW,
                    imageHeight: imgH
                )
            }
        case "r", "R":
            if currentScene == 9 {
                vision.stopTracking()
            } else if currentScene == 0 {
                vision.resetOpticalFlow()
            }
        default: break
        }
    }

    // MARK: - Input

    func currentInputTexture() -> MTLTexture? {
        if currentScene == 0 {
            // Optical flow: use animated texture
            return generateAnimatedTexture()
        }
        if useCameraInput, let camTex = cam?.texture {
            return camTex
        }
        return testTexture
    }

    // MARK: - Analysis Dispatch

    func runAnalysis(_ texture: MTLTexture) {
        switch currentScene {
        case 1:
            guard !vision.isProcessing else { return }
            vision.detectPose3D(texture)
        case 2:
            guard !vision.isProcessing else { return }
            vision.detectAnimals(texture)
        case 3:
            guard !vision.isProcessing else { return }
            vision.detectAnimalPose(texture)
        case 4:
            guard !vision.isProcessing else { return }
            vision.detectHumanRectangles(texture)
        case 5:
            guard !vision.isProcessing else { return }
            vision.detectRectangles(texture)
        case 6:
            runFeaturePrintAnalysis(texture)
        case 7:
            guard !vision.isProcessing else { return }
            vision.segmentForeground(texture)
        case 8:
            guard !vision.isProcessing else { return }
            vision.segmentPersonInstances(texture)
        case 9:
            if vision.isTracking {
                vision.trackObject(texture)
            }
        case 0:
            vision.computeOpticalFlow(texture)
        default: break
        }
    }

    func runFeaturePrintAnalysis(_ texture: MTLTexture) {
        guard !vision.isProcessing else { return }

        if featurePrintA == nil {
            // First: compute feature print of main image
            vision.generateFeaturePrint(texture)
            if let fp = vision.featurePrint {
                featurePrintA = fp
                comparingSecond = true
            }
        } else if featurePrintB == nil, comparingSecond, let texB = testTextureB {
            // Second: compute feature print of second image
            vision.generateFeaturePrint(texB)
            if let fp = vision.featurePrint, fp.data != featurePrintA?.data {
                featurePrintB = fp
                if let a = featurePrintA {
                    featureDistance = a.distance(to: fp)
                }
            }
        }
    }

    // MARK: - Drawing: Input Preview

    func drawInputPreview(_ texture: MTLTexture?) {
        guard let tex = texture else { return }

        let previewW: Float = 580
        let previewH: Float = 435
        let previewX: Float = 20
        let previewY: Float = 80

        noFill()
        stroke(Color(gray: 0.3))
        strokeWeight(1)
        rect(previewX - 1, previewY - 1, previewW + 2, previewH + 2)

        noStroke()
        let img = MImage(texture: tex)
        image(img, previewX, previewY, previewW, previewH)

        fill(Color(gray: 0.5))
        textSize(12)
        text(useCameraInput ? "Input: Camera" : "Input: Test Image", previewX, previewY - 8)

        // For feature print scene, also draw second image
        if currentScene == 6, let texB = testTextureB {
            let bX: Float = 20
            let bY: Float = 535
            let bW: Float = 180
            let bH: Float = 135
            let imgB = MImage(texture: texB)
            image(imgB, bX, bY, bW, bH)
            noFill()
            stroke(Color(gray: 0.3))
            rect(bX - 1, bY - 1, bW + 2, bH + 2)
            fill(Color(gray: 0.5))
            noStroke()
            textSize(10)
            text("Comparison Image", bX, bY - 6)
        }
    }

    // MARK: - Drawing: Results

    func drawResults(_ inputTexture: MTLTexture?) {
        let resultX: Float = 620
        let resultY: Float = 80
        let previewX: Float = 20
        let previewY: Float = 80
        let previewW: Float = 580
        let previewH: Float = 435

        fill(Color(gray: 0.6))
        textSize(14)
        text("Results:", resultX, resultY - 8)

        switch currentScene {
        case 1:
            drawPose3DOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawPose3DResults(resultX, resultY)
        case 2:
            drawAnimalOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawAnimalResults(resultX, resultY)
        case 3:
            drawAnimalPoseOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawAnimalPoseResults(resultX, resultY)
        case 4:
            drawHumanRectOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawHumanRectResults(resultX, resultY)
        case 5:
            drawRectangleOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawRectangleResults(resultX, resultY)
        case 6:
            drawFeaturePrintResults(resultX, resultY)
        case 7:
            drawForegroundMaskResult(resultX, resultY)
        case 8:
            drawPersonMaskResult(resultX, resultY)
        case 9:
            drawTrackingOverlay(previewX, previewY, previewW, previewH, inputTexture)
            drawTrackingResults(resultX, resultY)
        case 0:
            drawOpticalFlowResult(resultX, resultY)
        default: break
        }
    }

    // MARK: - Scene 1: 3D Body Pose

    func drawPose3DOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        // 3D pose doesn't have 2D overlay, but we can show a simple skeleton projection
        for pose in vision.poses3D {
            noFill()
            stroke(Color(hue: 0.55, saturation: 0.8, brightness: 1, alpha: 0.6))
            strokeWeight(2)

            // Project 3D coordinates to 2D (simple orthographic)
            let centerX = px + pw / 2
            let centerY = py + ph / 2
            let scale: Float = 300

            for lm in pose.landmarks where lm.confidence > 0.3 {
                let sx = centerX + lm.x * scale
                let sy = centerY - lm.y * scale  // Y up → Y down

                noStroke()
                let alpha = lm.confidence
                fill(Color(hue: 0.55, saturation: 1, brightness: 1, alpha: alpha))
                circle(sx, sy, 8)

                // Depth as size variation
                let depthSize = max(4, 8 + lm.z * 20)
                noFill()
                stroke(Color(hue: 0.15, saturation: 1, brightness: 1, alpha: alpha * 0.5))
                strokeWeight(1)
                circle(sx, sy, depthSize)
            }
        }
    }

    func drawPose3DResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("3D Bodies detected: \(vision.poses3D.count)", x, y + 20)

        for (i, pose) in vision.poses3D.enumerated() {
            let yPos = y + Float(i) * 200 + 50
            fill(Color(hue: 0.55, saturation: 0.5, brightness: 1))
            textSize(13)
            text("Body \(i + 1):", x, yPos)

            fill(Color(gray: 0.7))
            textSize(11)
            text("Confidence: \(String(format: "%.0f%%", pose.confidence * 100))", x + 10, yPos + 20)
            text("Body Height: \(String(format: "%.2f", pose.bodyHeight)) m", x + 10, yPos + 36)
            text("Joints: \(pose.landmarks.count)", x + 10, yPos + 52)

            // List some key joints
            let keyJoints = ["root_joint", "head_joint", "left_hand_joint", "right_hand_joint"]
            var offset: Float = 72
            for name in keyJoints {
                if let lm = pose.landmark(name) {
                    fill(Color(gray: 0.6))
                    textSize(10)
                    text(
                        "\(name): (\(String(format: "%.2f", lm.x)), \(String(format: "%.2f", lm.y)), \(String(format: "%.2f", lm.z)))",
                        x + 10, yPos + offset
                    )
                    offset += 14
                }
            }
        }

        if vision.poses3D.isEmpty {
            fill(Color(gray: 0.4))
            textSize(13)
            text("Waiting for body... (use Camera for best results)", x, y + 50)
        }
    }

    // MARK: - Scene 2: Animal Recognition

    func drawAnimalOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for det in vision.animalDetections {
            noFill()
            stroke(Color(hue: 0.1, saturation: 1, brightness: 1))
            strokeWeight(2)
            rect(
                px + det.x * scaleX,
                py + det.y * scaleY,
                det.w * scaleX,
                det.h * scaleY
            )

            fill(Color(hue: 0.1, saturation: 0.7, brightness: 1))
            noStroke()
            textSize(12)
            let conf = String(format: "%.0f%%", det.confidence * 100)
            text("\(det.label) \(conf)", px + det.x * scaleX + 4, py + det.y * scaleY - 6)
        }
    }

    func drawAnimalResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Animals detected: \(vision.animalDetections.count)", x, y + 20)

        for (i, det) in vision.animalDetections.enumerated() {
            let yPos = y + Float(i) * 50 + 50
            fill(Color(hue: 0.1, saturation: 0.7, brightness: 1))
            textSize(12)
            text("\(det.label)", x, yPos)
            fill(Color(gray: 0.6))
            textSize(11)
            text("Confidence: \(String(format: "%.1f%%", det.confidence * 100))", x + 10, yPos + 18)
            text("Box: (\(Int(det.x)), \(Int(det.y))) \(Int(det.w))x\(Int(det.h))", x + 10, yPos + 34)
        }

        if vision.animalDetections.isEmpty {
            fill(Color(gray: 0.4))
            textSize(13)
            text("No animals found (point camera at a cat/dog)", x, y + 50)
        }
    }

    // MARK: - Scene 3: Animal Pose

    func drawAnimalPoseOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for pose in vision.animalPoses {
            for lm in pose.landmarks where lm.confidence > 0.2 {
                let cx = px + lm.x * scaleX
                let cy = py + lm.y * scaleY

                noStroke()
                let alpha = lm.confidence
                fill(Color(hue: 0.3, saturation: 1, brightness: 1, alpha: alpha))
                circle(cx, cy, 10)

                fill(Color(r: 1, g: 1, b: 1, a: alpha))
                textSize(8)
                text(String(lm.name.prefix(12)), cx + 7, cy - 2)
            }
        }
    }

    func drawAnimalPoseResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Animal poses: \(vision.animalPoses.count)", x, y + 20)

        for (i, pose) in vision.animalPoses.enumerated() {
            let yPos = y + Float(i) * 50 + 50
            let highConf = pose.landmarks.filter { $0.confidence > 0.2 }
            fill(Color(gray: 0.7))
            textSize(12)
            text("Animal \(i + 1): \(highConf.count) joints", x, yPos)
            text("Confidence: \(String(format: "%.0f%%", pose.confidence * 100))", x + 10, yPos + 18)
        }

        if vision.animalPoses.isEmpty {
            fill(Color(gray: 0.4))
            textSize(13)
            text("No animal pose found (point camera at a cat/dog)", x, y + 50)
        }
    }

    // MARK: - Scene 4: Human Rectangles

    func drawHumanRectOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for (i, det) in vision.humanRectangles.enumerated() {
            let hue = Float(i) * 0.15
            noFill()
            stroke(Color(hue: hue, saturation: 1, brightness: 1))
            strokeWeight(2)
            rect(
                px + det.x * scaleX,
                py + det.y * scaleY,
                det.w * scaleX,
                det.h * scaleY
            )

            fill(Color(hue: hue, saturation: 0.7, brightness: 1))
            noStroke()
            textSize(11)
            let conf = String(format: "%.0f%%", det.confidence * 100)
            text("Human \(i + 1) [\(conf)]", px + det.x * scaleX + 4, py + det.y * scaleY - 6)
        }
    }

    func drawHumanRectResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Humans detected: \(vision.humanRectangles.count)", x, y + 20)

        for (i, det) in vision.humanRectangles.enumerated() {
            let yPos = y + Float(i) * 40 + 50
            fill(Color(gray: 0.7))
            textSize(12)
            text("Person \(i + 1): (\(Int(det.x)), \(Int(det.y))) \(Int(det.w))x\(Int(det.h))", x, yPos)
            text("Confidence: \(String(format: "%.1f%%", det.confidence * 100))", x + 10, yPos + 18)
        }

        if vision.humanRectangles.isEmpty {
            fill(Color(gray: 0.4))
            textSize(13)
            text("No human bodies found (use Camera)", x, y + 50)
        }
    }

    // MARK: - Scene 5: Rectangle Detection

    func drawRectangleOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        for (i, r) in vision.rectangles.enumerated() {
            let hue = Float(i) * 0.12
            noFill()
            stroke(Color(hue: hue, saturation: 1, brightness: 1))
            strokeWeight(2)

            // Draw 4 edges of the quadrilateral
            let tl = SIMD2<Float>(px + r.topLeft.x * scaleX, py + r.topLeft.y * scaleY)
            let tr = SIMD2<Float>(px + r.topRight.x * scaleX, py + r.topRight.y * scaleY)
            let br = SIMD2<Float>(px + r.bottomRight.x * scaleX, py + r.bottomRight.y * scaleY)
            let bl = SIMD2<Float>(px + r.bottomLeft.x * scaleX, py + r.bottomLeft.y * scaleY)

            line(tl.x, tl.y, tr.x, tr.y)
            line(tr.x, tr.y, br.x, br.y)
            line(br.x, br.y, bl.x, bl.y)
            line(bl.x, bl.y, tl.x, tl.y)

            // Center dot
            let c = r.center
            noStroke()
            fill(Color(hue: hue, saturation: 1, brightness: 1))
            circle(px + c.x * scaleX, py + c.y * scaleY, 6)
        }
    }

    func drawRectangleResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Rectangles detected: \(vision.rectangles.count)", x, y + 20)

        fill(Color(gray: 0.5))
        textSize(10)
        text("Config: minAspect=\(String(format: "%.1f", vision.rectangleMinAspectRatio)), maxAspect=\(String(format: "%.1f", vision.rectangleMaxAspectRatio)), minSize=\(String(format: "%.2f", vision.rectangleMinSize))", x, y + 40)

        for (i, r) in vision.rectangles.enumerated() {
            let yPos = y + Float(i) * 50 + 60
            let hue = Float(i) * 0.12
            fill(Color(hue: hue, saturation: 0.7, brightness: 1))
            textSize(12)
            text("Rect \(i + 1):", x, yPos)
            fill(Color(gray: 0.6))
            textSize(10)
            text("TL: (\(Int(r.topLeft.x)), \(Int(r.topLeft.y)))  TR: (\(Int(r.topRight.x)), \(Int(r.topRight.y)))", x + 10, yPos + 16)
            text("BL: (\(Int(r.bottomLeft.x)), \(Int(r.bottomLeft.y)))  BR: (\(Int(r.bottomRight.x)), \(Int(r.bottomRight.y)))", x + 10, yPos + 30)
            text("Confidence: \(String(format: "%.0f%%", r.confidence * 100))", x + 10, yPos + 44)
        }
    }

    // MARK: - Scene 6: Feature Print

    func drawFeaturePrintResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Image Feature Print", x, y + 20)

        if let fpA = featurePrintA {
            fill(Color(hue: 0.6, saturation: 0.5, brightness: 1))
            textSize(12)
            text("Image A feature vector:", x, y + 50)
            fill(Color(gray: 0.6))
            textSize(11)
            text("Dimensions: \(fpA.count)", x + 10, y + 68)
            text("Type: \(fpA.elementType)", x + 10, y + 84)

            // Visualize first 128 dimensions as a bar chart
            let vizY = y + 100
            let barW: Float = 2
            let maxH: Float = 60
            let vizCount = min(128, fpA.count)

            fill(Color(gray: 0.5))
            textSize(10)
            text("First \(vizCount) dimensions:", x, vizY)

            for i in 0..<vizCount {
                let v = fpA.data[i]
                let barH = abs(v) * maxH * 0.5
                let barX = x + Float(i) * (barW + 1)
                let barY = vizY + 16 + maxH / 2

                noStroke()
                if v >= 0 {
                    fill(Color(hue: 0.6, saturation: 0.8, brightness: 0.9, alpha: 0.8))
                    rect(barX, barY - barH, barW, barH)
                } else {
                    fill(Color(hue: 0.0, saturation: 0.8, brightness: 0.9, alpha: 0.8))
                    rect(barX, barY, barW, barH)
                }
            }

            // Second image results
            if let fpB = featurePrintB, let dist = featureDistance {
                let secY = vizY + maxH + 40

                fill(Color(hue: 0.15, saturation: 0.5, brightness: 1))
                textSize(12)
                text("Image B feature vector:", x, secY)
                fill(Color(gray: 0.6))
                textSize(11)
                text("Dimensions: \(fpB.count)", x + 10, secY + 18)

                // Distance
                fill(.white)
                textSize(14)
                text("Cosine Distance: \(String(format: "%.4f", dist))", x, secY + 46)

                // Similarity bar
                let similarity = max(0, 1.0 - dist)
                let barWidth: Float = 300
                noStroke()
                fill(Color(gray: 0.15))
                rect(x, secY + 60, barWidth, 20)
                let hue: Float = similarity * 0.33  // red=different, green=similar
                fill(Color(hue: hue, saturation: 0.9, brightness: 0.9))
                rect(x, secY + 60, barWidth * similarity, 20)

                fill(.white)
                textSize(11)
                text("\(String(format: "%.1f%%", similarity * 100)) similar", x + barWidth + 10, secY + 75)
            } else if comparingSecond {
                fill(Color(gray: 0.4))
                textSize(12)
                text("Computing feature print B...", x, vizY + maxH + 40)
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(13)
            text("Computing feature print A...", x, y + 50)
        }
    }

    // MARK: - Scene 7: Foreground Instance Mask

    func drawForegroundMaskResult(_ x: Float, _ y: Float) {
        if let maskTex = vision.foregroundMaskTexture {
            fill(Color(gray: 0.5))
            textSize(12)
            text("Foreground Instance Mask:", x, y + 10)

            let maskW: Float = 320
            let maskH: Float = 240
            image(maskTex, x, y + 20, maskW, maskH)

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x - 1, y + 19, maskW + 2, maskH + 2)
            noStroke()
        }

        if let mask = vision.foregroundInstanceMask {
            let yOff: Float = vision.foregroundMaskTexture != nil ? 290 : 20
            fill(Color(gray: 0.7))
            textSize(12)
            text("Mask size: \(mask.width) x \(mask.height)", x, y + yOff)
            text("Instances: \(mask.instanceCount)", x, y + yOff + 18)

            // Show each instance's coverage
            for i in 0..<mask.instanceCount {
                if let instanceData = mask.mask(forInstance: i) {
                    let coverage = instanceData.reduce(0, +) / Float(max(1, instanceData.count))
                    let yPos = y + yOff + 40 + Float(i) * 22
                    let hue = Float(i) / max(1, Float(mask.instanceCount))
                    fill(Color(hue: hue, saturation: 0.7, brightness: 1))
                    textSize(11)
                    text("Instance \(i + 1): \(String(format: "%.1f%%", coverage * 100)) coverage", x + 10, yPos)
                }
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Analyzing... (works best with camera)", x, y + 20)
        }
    }

    // MARK: - Scene 8: Person Instance Mask

    func drawPersonMaskResult(_ x: Float, _ y: Float) {
        if let maskTex = vision.personMaskTexture {
            fill(Color(gray: 0.5))
            textSize(12)
            text("Person Instance Mask:", x, y + 10)

            let maskW: Float = 320
            let maskH: Float = 240
            image(maskTex, x, y + 20, maskW, maskH)

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x - 1, y + 19, maskW + 2, maskH + 2)
            noStroke()
        }

        if let mask = vision.personInstanceMask {
            let yOff: Float = vision.personMaskTexture != nil ? 290 : 20
            fill(Color(gray: 0.7))
            textSize(12)
            text("Mask size: \(mask.width) x \(mask.height)", x, y + yOff)
            text("Person instances: \(mask.instanceCount)", x, y + yOff + 18)

            for i in 0..<mask.instanceCount {
                if let instanceData = mask.mask(forInstance: i) {
                    let coverage = instanceData.reduce(0, +) / Float(max(1, instanceData.count))
                    let yPos = y + yOff + 40 + Float(i) * 22
                    fill(Color(hue: 0.6, saturation: 0.7, brightness: 1))
                    textSize(11)
                    text("Person \(i + 1): \(String(format: "%.1f%%", coverage * 100)) coverage", x + 10, yPos)
                }
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Analyzing... (use Camera to see people)", x, y + 20)
        }
    }

    // MARK: - Scene 9: Object Tracking

    func drawTrackingOverlay(_ px: Float, _ py: Float, _ pw: Float, _ ph: Float, _ tex: MTLTexture?) {
        guard let tex = tex else { return }
        let scaleX = pw / Float(tex.width)
        let scaleY = ph / Float(tex.height)

        if let tracked = vision.trackedObject, tracked.isTracking {
            // Draw tracking box
            noFill()
            stroke(Color(hue: 0.33, saturation: 1, brightness: 1))
            strokeWeight(3)
            rect(
                px + tracked.x * scaleX,
                py + tracked.y * scaleY,
                tracked.w * scaleX,
                tracked.h * scaleY
            )

            // Crosshair at center
            let cx = px + (tracked.x + tracked.w / 2) * scaleX
            let cy = py + (tracked.y + tracked.h / 2) * scaleY
            stroke(Color(hue: 0.33, saturation: 1, brightness: 1, alpha: 0.5))
            strokeWeight(1)
            line(cx - 15, cy, cx + 15, cy)
            line(cx, cy - 15, cx, cy + 15)
        } else if !vision.isTracking {
            // Show hint: draw initial tracking region
            noFill()
            stroke(Color(gray: 0.5, alpha: 0.4))
            strokeWeight(1)
            let cx = px + pw / 2
            let cy = py + ph / 2
            let tw: Float = 200 * scaleX
            let th: Float = 200 * scaleY
            rect(cx - tw / 2, cy - th / 2, tw, th)

            fill(Color(gray: 0.5, alpha: 0.5))
            noStroke()
            textSize(11)
            text("Press T to start tracking center", cx - 80, cy + th / 2 + 16)
        }
    }

    func drawTrackingResults(_ x: Float, _ y: Float) {
        fill(.white)
        textSize(14)
        text("Object Tracking", x, y + 20)

        fill(Color(gray: 0.6))
        textSize(12)
        text("Status: \(vision.isTracking ? "TRACKING" : "STOPPED")", x, y + 45)

        if vision.isTracking {
            noStroke()
            fill(Color(hue: 0.33, saturation: 1, brightness: 1))
            circle(x + 80, y + 41, 8)
        } else {
            noStroke()
            fill(Color(gray: 0.4))
            circle(x + 80, y + 41, 8)
        }

        if let tracked = vision.trackedObject {
            fill(Color(gray: 0.7))
            textSize(11)
            text("Position: (\(Int(tracked.x)), \(Int(tracked.y)))", x + 10, y + 70)
            text("Size: \(Int(tracked.w)) x \(Int(tracked.h))", x + 10, y + 86)
            text("Confidence: \(String(format: "%.1f%%", tracked.confidence * 100))", x + 10, y + 102)
            text("Is Tracking: \(tracked.isTracking)", x + 10, y + 118)
        }

        fill(Color(gray: 0.5))
        textSize(11)
        text("[T] Start tracking  [R] Reset  [C] Camera", x, y + 150)
        text("Tracking threshold: \(String(format: "%.1f", vision.trackingConfidenceThreshold))", x, y + 168)
    }

    // MARK: - Scene 0: Optical Flow

    func drawOpticalFlowResult(_ x: Float, _ y: Float) {
        if let flowTex = vision.opticalFlowTexture {
            fill(Color(gray: 0.5))
            textSize(12)
            text("Optical Flow Texture:", x, y + 10)

            let texW: Float = 320
            let texH: Float = 240
            image(flowTex, x, y + 20, texW, texH)

            noFill()
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            rect(x - 1, y + 19, texW + 2, texH + 2)
            noStroke()
        }

        if let flow = vision.opticalFlow {
            let yOff: Float = vision.opticalFlowTexture != nil ? 290 : 20

            fill(Color(gray: 0.7))
            textSize(12)
            text("Flow field: \(flow.width) x \(flow.height)", x, y + yOff)
            text("Average magnitude: \(String(format: "%.2f", flow.averageMagnitude)) px", x, y + yOff + 18)

            // Draw a quiver plot (sampled flow vectors)
            let plotX = x
            let plotY = y + yOff + 40
            let plotW: Float = 300
            let plotH: Float = 200
            let stepX = max(1, flow.width / 20)
            let stepY = max(1, flow.height / 15)
            let cellW = plotW / Float(flow.width) * Float(stepX)
            let cellH = plotH / Float(flow.height) * Float(stepY)

            noFill()
            stroke(Color(gray: 0.2))
            strokeWeight(1)
            rect(plotX, plotY, plotW, plotH)

            for fy in stride(from: 0, to: flow.height, by: stepY) {
                for fx in stride(from: 0, to: flow.width, by: stepX) {
                    if let v = flow.flow(at: fx, y: fy) {
                        let px = plotX + Float(fx) / Float(flow.width) * plotW
                        let py = plotY + Float(fy) / Float(flow.height) * plotH
                        let mag = sqrt(v.x * v.x + v.y * v.y)
                        let maxArrow = min(cellW, cellH) * 0.8
                        let arrowLen = min(mag * 2, maxArrow)

                        if mag > 0.5 {
                            let nx = v.x / mag
                            let ny = v.y / mag
                            let hue = atan2(v.y, v.x) / (2 * Float.pi) + 0.5
                            stroke(Color(hue: hue, saturation: 0.9, brightness: 0.9, alpha: min(1, mag / 5)))
                            strokeWeight(1)
                            line(px, py, px + nx * arrowLen, py + ny * arrowLen)
                        }
                    }
                }
            }
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            text("Waiting for optical flow...", x, y + 20)
            text("(animated test image generates motion)", x, y + 40)
        }

        fill(Color(gray: 0.5))
        textSize(11)
        text("[R] Reset flow  [C] Camera", x, y + (vision.opticalFlow != nil ? 560 : 70))
    }

    // MARK: - HUD

    func drawHUD() {
        noStroke()
        fill(Color(r: 0, g: 0, b: 0, a: 0.7))
        rect(0, 0, width, 60)

        fill(.white)
        textSize(22)
        let key = currentScene
        let sceneName = sceneNames[key] ?? "Unknown"
        text("Scene \(key): \(sceneName)", 20, 38)

        fill(Color(gray: 0.5))
        textSize(11)
        text("[1-9, 0] Switch Scene  [C] Toggle Camera  [I] Toggle Info", 20, height - 12)

        if showInferenceTime && vision.inferenceTime > 0 {
            fill(Color(hue: 0.33, saturation: 0.8, brightness: 0.9))
            textSize(12)
            let ms = String(format: "%.1f ms", vision.inferenceTime * 1000)
            text("Inference: \(ms)", width - 160, 38)

            if vision.isProcessing {
                noStroke()
                fill(Color(hue: 0.1, saturation: 1, brightness: 1))
                circle(width - 175, 34, 8)
            } else {
                noStroke()
                fill(Color(hue: 0.33, saturation: 1, brightness: 1))
                circle(width - 175, 34, 8)
            }
        }

        fill(useCameraInput ? Color(hue: 0.33, saturation: 0.8, brightness: 0.9) : Color(gray: 0.5))
        textSize(11)
        text(useCameraInput ? "CAMERA" : "TEST IMAGE", width - 160, 16)
    }

    // MARK: - Test Image Generation

    func generateTestTexture() {
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

        // Face-like circle (for human rectangle / person mask detection)
        drawCircle(&pixels, w, h, cx: 350, cy: 250, radius: 100, r: 220, g: 200, b: 180)
        drawCircle(&pixels, w, h, cx: 320, cy: 230, radius: 12, r: 40, g: 30, b: 30)  // left eye
        drawCircle(&pixels, w, h, cx: 380, cy: 230, radius: 12, r: 40, g: 30, b: 30)  // right eye
        // Body shape below face
        drawRect(&pixels, w, h, x: 290, y: 350, rw: 120, rh: 200, r: 180, g: 160, b: 140)
        // Arms
        drawRect(&pixels, w, h, x: 210, y: 370, rw: 80, rh: 30, r: 180, g: 160, b: 140)
        drawRect(&pixels, w, h, x: 410, y: 370, rw: 80, rh: 30, r: 180, g: 160, b: 140)

        // Rectangles (for rectangle detection)
        drawRect(&pixels, w, h, x: 750, y: 120, rw: 200, rh: 150, r: 255, g: 100, b: 50)
        drawRect(&pixels, w, h, x: 850, y: 350, rw: 120, rh: 120, r: 50, g: 150, b: 255)
        drawRect(&pixels, w, h, x: 1000, y: 200, rw: 160, rh: 80, r: 100, g: 255, b: 50)

        // Animal-like shape (simple cat silhouette)
        drawCircle(&pixels, w, h, cx: 600, cy: 500, radius: 60, r: 160, g: 120, b: 80) // body
        drawCircle(&pixels, w, h, cx: 660, cy: 470, radius: 35, r: 160, g: 120, b: 80) // head
        // Ears (small triangles approximated as circles)
        drawCircle(&pixels, w, h, cx: 645, cy: 440, radius: 12, r: 160, g: 120, b: 80)
        drawCircle(&pixels, w, h, cx: 678, cy: 440, radius: 12, r: 160, g: 120, b: 80)
        // Eyes
        drawCircle(&pixels, w, h, cx: 650, cy: 465, radius: 5, r: 200, g: 220, b: 50)
        drawCircle(&pixels, w, h, cx: 670, cy: 465, radius: 5, r: 200, g: 220, b: 50)

        // High contrast edges
        drawRect(&pixels, w, h, x: 100, y: 620, rw: 500, rh: 8, r: 255, g: 255, b: 255)

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: w * 4
        )

        testTexture = tex
    }

    func generateTestTextureB() {
        // Generate a different image for feature print comparison
        let w = 640
        let h = 480
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

        // Different gradient (vertical blue)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let gradV = UInt8(Float(y) / Float(h) * 120 + 30)
                pixels[i] = gradV + 50  // B
                pixels[i + 1] = gradV / 2  // G
                pixels[i + 2] = UInt8(Float(x) / Float(w) * 60)  // R
                pixels[i + 3] = 255
            }
        }

        // Different shapes (circles, triangles)
        drawCircle(&pixels, w, h, cx: 320, cy: 240, radius: 120, r: 255, g: 200, b: 100)
        drawCircle(&pixels, w, h, cx: 150, cy: 150, radius: 60, r: 100, g: 255, b: 200)
        drawRect(&pixels, w, h, x: 400, y: 300, rw: 180, rh: 100, r: 200, g: 100, b: 255)

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: w * 4
        )

        testTextureB = tex
    }

    func generateAnimatedTexture() -> MTLTexture? {
        // Generate a moving pattern for optical flow
        let w = 640
        let h = 480
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif

        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = device.makeTexture(descriptor: desc) else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        flowFrameCount += 1

        let t = Float(flowFrameCount) * 0.05

        // Background
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                pixels[i] = 30
                pixels[i + 1] = 30
                pixels[i + 2] = 40
                pixels[i + 3] = 255
            }
        }

        // Moving circles
        let cx1 = Int(320 + sin(t) * 150)
        let cy1 = Int(240 + cos(t) * 100)
        drawCircle(&pixels, w, h, cx: cx1, cy: cy1, radius: 60, r: 255, g: 100, b: 50)

        let cx2 = Int(320 + cos(t * 0.7) * 200)
        let cy2 = Int(240 + sin(t * 0.7) * 80)
        drawCircle(&pixels, w, h, cx: cx2, cy: cy2, radius: 40, r: 50, g: 200, b: 255)

        // Moving rectangle
        let rx = Int(sin(t * 0.5) * 200 + 320)
        let ry = Int(cos(t * 0.3) * 150 + 240)
        drawRect(&pixels, w, h, x: rx - 50, y: ry - 30, rw: 100, rh: 60, r: 100, g: 255, b: 100)

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: w * 4
        )

        return tex
    }

    // MARK: - Drawing Helpers

    func drawCircle(_ pixels: inout [UInt8], _ w: Int, _ h: Int, cx: Int, cy: Int, radius: Int, r: UInt8, g: UInt8, b: UInt8) {
        for py in max(0, cy - radius)..<min(h, cy + radius + 1) {
            for px in max(0, cx - radius)..<min(w, cx + radius + 1) {
                let dx = px - cx
                let dy = py - cy
                if dx * dx + dy * dy <= radius * radius {
                    let i = (py * w + px) * 4
                    pixels[i] = b
                    pixels[i + 1] = g
                    pixels[i + 2] = r
                    pixels[i + 3] = 255
                }
            }
        }
    }

    func drawRect(_ pixels: inout [UInt8], _ w: Int, _ h: Int, x: Int, y: Int, rw: Int, rh: Int, r: UInt8, g: UInt8, b: UInt8) {
        for py in max(0, y)..<min(h, y + rh) {
            for px in max(0, x)..<min(w, x + rw) {
                let i = (py * w + px) * 4
                pixels[i] = b
                pixels[i + 1] = g
                pixels[i + 2] = r
                pixels[i + 3] = 255
            }
        }
    }
}
