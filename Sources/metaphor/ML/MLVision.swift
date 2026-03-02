import CoreML
import CoreVideo
import Metal
import QuartzCore
import Vision

// MARK: - Thread-safe Vision Result Buffer

private enum VisionResultValue {
    case classifications([MLClassification], Double)
    case detections([MLDetection], Double)
    case poses([MLPose], Double)
    case segmentMask(MLSegmentMask, CVPixelBuffer?, Double)
    case faces([MLFace], Double)
    case texts([MLText], Double)
    case saliency(MLSaliency, Double)
    case barcodes([MLBarcode], Double)
    case contours([MLContour], Double)
    case poses3D([MLPose3D], Double)
    case animalDetections([MLDetection], Double)
    case animalPoses([MLPose], Double)
    case humanRectangles([MLDetection], Double)
    case rectangles([MLRectangle], Double)
    case featurePrint(MLFeaturePrint, Double)
    case foregroundInstanceMask(MLInstanceMask, CVPixelBuffer?, Double)
    case personInstanceMask(MLInstanceMask, CVPixelBuffer?, Double)
    case trackedObject(MLTrackedObject, Double)
    case opticalFlow(MLOpticalFlow, CVPixelBuffer?, Double)
}

private final class VisionResultBuffer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _results: [VisionResultValue] = []

    func store(_ result: VisionResultValue) {
        lock.lock()
        _results.append(result)
        lock.unlock()
    }

    func takeAll() -> [VisionResultValue] {
        lock.lock()
        let r = _results
        _results = []
        lock.unlock()
        return r
    }
}

// MARK: - Mask Extraction Helper (file-private)

/// CVPixelBuffer から Float 配列を抽出するヘルパー
private func extractFloatMaskData(from pixelBuffer: CVPixelBuffer) -> [Float] {
    let maskWidth = CVPixelBufferGetWidth(pixelBuffer)
    let maskHeight = CVPixelBufferGetHeight(pixelBuffer)

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    var floatData = [Float](repeating: 0, count: maskWidth * maskHeight)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return floatData }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)

    if formatType == kCVPixelFormatType_OneComponent8 {
        for y in 0..<maskHeight {
            let row = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<maskWidth {
                floatData[y * maskWidth + x] = Float(row[x]) / 255.0
            }
        }
    } else if formatType == kCVPixelFormatType_OneComponent32Float {
        for y in 0..<maskHeight {
            let row = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for x in 0..<maskWidth {
                floatData[y * maskWidth + x] = row[x]
            }
        }
    } else if formatType == kCVPixelFormatType_32BGRA {
        for y in 0..<maskHeight {
            let row = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<maskWidth {
                floatData[y * maskWidth + x] = Float(row[x * 4]) / 255.0
            }
        }
    }

    return floatData
}

// MARK: - Tracking State (thread-safe)

private final class TrackingState: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _observation: VNDetectedObjectObservation?
    private nonisolated(unsafe) var _isProcessing: Bool = false

    func setObservation(_ obs: VNDetectedObjectObservation?) {
        lock.lock()
        _observation = obs
        lock.unlock()
    }

    func getObservation() -> VNDetectedObjectObservation? {
        lock.lock()
        let obs = _observation
        lock.unlock()
        return obs
    }

    func setProcessing(_ v: Bool) {
        lock.lock()
        _isProcessing = v
        lock.unlock()
    }

    func getProcessing() -> Bool {
        lock.lock()
        let v = _isProcessing
        lock.unlock()
        return v
    }
}

// MARK: - MLVision

/// Vision フレームワークラッパー
///
/// 画像分類、オブジェクト検出、ポーズ推定、セグメンテーション、
/// テキスト認識、顔検出、サリエンシーなどの Vision API をラップする。
/// 全て非同期推論を実行し、draw loop をブロックしない。
///
/// ```swift
/// var vision: MLVision!
/// func setup() {
///     vision = createVision()
/// }
/// func draw() {
///     vision.update()
///     vision.classify(cam.texture!)
///     for c in vision.classifications {
///         text("\(c.label): \(c.confidence)", 10, 30)
///     }
/// }
/// ```
@MainActor
public final class MLVision {

    // MARK: - Public Results

    /// 最新の分類結果
    public private(set) var classifications: [MLClassification] = []

    /// 最新のオブジェクト検出結果
    public private(set) var detections: [MLDetection] = []

    /// 最新のポーズ推定結果
    public private(set) var poses: [MLPose] = []

    /// 最新のセグメンテーションマスク
    public private(set) var segmentMask: MLSegmentMask?

    /// セグメンテーションマスクのテクスチャ（描画用）
    public private(set) var segmentMaskTexture: MImage?

    /// 最新の顔検出結果
    public private(set) var faces: [MLFace] = []

    /// 最新のテキスト認識結果
    public private(set) var texts: [MLText] = []

    /// 最新のサリエンシー
    public private(set) var saliency: MLSaliency?

    /// サリエンシーテクスチャ（描画用）
    public private(set) var saliencyTexture: MImage?

    /// 最新のバーコード/QR検出結果
    public private(set) var barcodes: [MLBarcode] = []

    /// 最新の輪郭検出結果
    public private(set) var contours: [MLContour] = []

    /// 最新の3Dポーズ推定結果
    public private(set) var poses3D: [MLPose3D] = []

    /// 最新の動物検出結果
    public private(set) var animalDetections: [MLDetection] = []

    /// 最新の動物ポーズ推定結果
    public private(set) var animalPoses: [MLPose] = []

    /// 最新の人物矩形検出結果
    public private(set) var humanRectangles: [MLDetection] = []

    /// 最新の矩形検出結果
    public private(set) var rectangles: [MLRectangle] = []

    /// 最新の画像特徴ベクトル
    public private(set) var featurePrint: MLFeaturePrint?

    /// 最新の前景インスタンスマスク
    public private(set) var foregroundInstanceMask: MLInstanceMask?

    /// 前景インスタンスマスクのテクスチャ（統合マスク、描画用）
    public private(set) var foregroundMaskTexture: MImage?

    /// 最新の人物インスタンスマスク
    public private(set) var personInstanceMask: MLInstanceMask?

    /// 人物インスタンスマスクのテクスチャ（統合マスク、描画用）
    public private(set) var personMaskTexture: MImage?

    /// 最新のオブジェクトトラッキング結果
    public private(set) var trackedObject: MLTrackedObject?

    /// オブジェクトトラッキングが有効かどうか
    public private(set) var isTracking: Bool = false

    /// 最新のオプティカルフロー結果
    public private(set) var opticalFlow: MLOpticalFlow?

    /// オプティカルフローテクスチャ（可視化用）
    public private(set) var opticalFlowTexture: MImage?

    /// 推論実行中かどうか
    public private(set) var isProcessing: Bool = false

    /// 最後の推論にかかった時間（秒）
    public private(set) var inferenceTime: Double = 0

    // MARK: - Configuration

    /// 分類結果の最大数
    public var maxClassifications: Int = 5

    /// 検出の信頼度閾値
    public var confidenceThreshold: Float = 0.5

    /// テキスト認識の認識レベル
    public var textRecognitionLevel: VNRequestTextRecognitionLevel = .accurate

    /// テキスト認識の言語
    public var textRecognitionLanguages: [String] = ["en", "ja"]

    /// 顔ランドマーク取得を有効にするか
    public var detectFaceLandmarks: Bool = true

    /// 矩形検出: 最小アスペクト比
    public var rectangleMinAspectRatio: Float = 0.0

    /// 矩形検出: 最大アスペクト比
    public var rectangleMaxAspectRatio: Float = 1.0

    /// 矩形検出: 最小サイズ（画像比率 0.0〜1.0）
    public var rectangleMinSize: Float = 0.1

    /// 矩形検出: 最大検出数
    public var maxRectangles: Int = 10

    /// オプティカルフロー: 計算精度レベル
    public var opticalFlowAccuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy = .medium

    /// トラッキング: 信頼度閾値（これ以下でトラッキング失敗とみなす）
    public var trackingConfidenceThreshold: Float = 0.3

    // MARK: - Private

    private let device: MTLDevice
    private let converter: MLTextureConverter
    private let resultBuffer = VisionResultBuffer()
    private let inferenceQueue = DispatchQueue(label: "metaphor.vision.inference", qos: .userInitiated)

    /// カスタム CoreML モデル（Vision で使用）
    private var customModel: VNCoreMLModel?

    /// トラッキング用状態（スレッドセーフ）
    private let trackingState = TrackingState()

    /// トラッキング用 VNSequenceRequestHandler（フレーム間で永続）
    private var trackingSequenceHandler: VNSequenceRequestHandler?

    /// トラッキング画像サイズ（座標変換用）
    private var trackingImageWidth: Float = 0
    private var trackingImageHeight: Float = 0

    /// オプティカルフロー用: 前フレームの CVPixelBuffer
    private var previousFramePixelBuffer: CVPixelBuffer?

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.converter = MLTextureConverter(device: device, commandQueue: commandQueue)
    }

    // MARK: - Custom Model Loading

    /// Vision で使用するカスタム CoreML モデルを読み込む
    public func loadModel(_ path: String, computeUnit: MLComputeUnit = .all) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MLError.modelNotFound(path)
        }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnit.coreMLUnit
        let mlModel = try CoreML.MLModel(contentsOf: url, configuration: config)
        self.customModel = try VNCoreMLModel(for: mlModel)
    }

    /// バンドルリソースからカスタムモデルを読み込む
    public func loadModel(named name: String, computeUnit: MLComputeUnit = .all) throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") else {
            throw MLError.modelNotFound(name)
        }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnit.coreMLUnit
        let mlModel = try CoreML.MLModel(contentsOf: url, configuration: config)
        self.customModel = try VNCoreMLModel(for: mlModel)
    }

    // MARK: - Update (per-frame)

    /// 毎フレーム呼ぶ更新メソッド（draw() の先頭で呼ぶ）
    /// 非同期推論の結果を公開プロパティに反映する
    public func update() {
        let results = resultBuffer.takeAll()
        guard !results.isEmpty else { return }
        isProcessing = false

        for result in results {
            switch result {
            case .classifications(let cls, let time):
                classifications = cls
                inferenceTime = time

            case .detections(let dets, let time):
                detections = dets
                inferenceTime = time

            case .poses(let p, let time):
                poses = p
                inferenceTime = time

            case .segmentMask(let mask, let pixelBuffer, let time):
                segmentMask = mask
                if let pb = pixelBuffer, let tex = converter.texture(from: pb) {
                    segmentMaskTexture = MImage(texture: tex)
                }
                inferenceTime = time

            case .faces(let f, let time):
                faces = f
                inferenceTime = time

            case .texts(let t, let time):
                texts = t
                inferenceTime = time

            case .saliency(let s, let time):
                saliency = s
                inferenceTime = time

            case .barcodes(let b, let time):
                barcodes = b
                inferenceTime = time

            case .contours(let c, let time):
                contours = c
                inferenceTime = time

            case .poses3D(let p, let time):
                poses3D = p
                inferenceTime = time

            case .animalDetections(let dets, let time):
                animalDetections = dets
                inferenceTime = time

            case .animalPoses(let p, let time):
                animalPoses = p
                inferenceTime = time

            case .humanRectangles(let dets, let time):
                humanRectangles = dets
                inferenceTime = time

            case .rectangles(let rects, let time):
                rectangles = rects
                inferenceTime = time

            case .featurePrint(let fp, let time):
                featurePrint = fp
                inferenceTime = time

            case .foregroundInstanceMask(let mask, let pixelBuffer, let time):
                foregroundInstanceMask = mask
                if let pb = pixelBuffer, let tex = converter.texture(from: pb) {
                    foregroundMaskTexture = MImage(texture: tex)
                }
                inferenceTime = time

            case .personInstanceMask(let mask, let pixelBuffer, let time):
                personInstanceMask = mask
                if let pb = pixelBuffer, let tex = converter.texture(from: pb) {
                    personMaskTexture = MImage(texture: tex)
                }
                inferenceTime = time

            case .trackedObject(let obj, let time):
                trackedObject = obj
                trackingState.setProcessing(false)
                if !obj.isTracking {
                    isTracking = false
                }
                inferenceTime = time

            case .opticalFlow(let flow, let pixelBuffer, let time):
                opticalFlow = flow
                if let pb = pixelBuffer, let tex = converter.texture(from: pb) {
                    opticalFlowTexture = MImage(texture: tex)
                }
                inferenceTime = time
            }
        }
    }

    // MARK: - Classification

    /// 画像分類を実行（非同期）
    public func classify(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let maxResults = maxClassifications
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNClassifyImageRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                let results = (request.results ?? [])
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(maxResults)
                    .map { MLClassification(label: $0.identifier, confidence: $0.confidence) }

                buffer.store(.classifications(Array(results), elapsed))
            } catch {
                print("[metaphor] Vision classify error: \(error)")
                buffer.store(.classifications([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage を分類
    public func classify(_ image: MImage) {
        classify(image.texture)
    }

    // MARK: - Object Detection (with custom model)

    /// カスタムモデルでオブジェクト検出（非同期）
    public func detect(_ texture: MTLTexture) {
        guard !isProcessing, let model = customModel else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let threshold = confidenceThreshold
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                let detections = (request.results as? [VNRecognizedObjectObservation] ?? [])
                    .filter { $0.confidence >= threshold }
                    .map { obs -> MLDetection in
                        let bb = obs.boundingBox
                        // Vision: 正規化座標（左下原点）→ ピクセル座標（左上原点）
                        return MLDetection(
                            label: obs.labels.first?.identifier ?? "unknown",
                            confidence: obs.confidence,
                            x: Float(bb.origin.x) * imageWidth,
                            y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                            w: Float(bb.size.width) * imageWidth,
                            h: Float(bb.size.height) * imageHeight
                        )
                    }

                buffer.store(.detections(detections, elapsed))
            } catch {
                print("[metaphor] Vision detect error: \(error)")
                buffer.store(.detections([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で検出
    public func detect(_ image: MImage) {
        detect(image.texture)
    }

    // MARK: - Pose Estimation

    /// ボディポーズ推定（非同期）
    public func detectPose(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectHumanBodyPoseRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var poses: [MLPose] = []
                for obs in (request.results ?? []) {
                    var landmarks: [MLLandmark] = []
                    if let points = try? obs.recognizedPoints(.all) {
                        for (key, point) in points {
                            let name = "\(key.rawValue)"
                            let lm = MLLandmark(
                                name: name,
                                x: Float(point.location.x) * imageWidth,
                                y: (1 - Float(point.location.y)) * imageHeight,
                                confidence: Float(point.confidence)
                            )
                            landmarks.append(lm)
                        }
                    }
                    poses.append(MLPose(landmarks: landmarks, confidence: obs.confidence))
                }

                buffer.store(.poses(poses, elapsed))
            } catch {
                print("[metaphor] Vision pose error: \(error)")
                buffer.store(.poses([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でポーズ推定
    public func detectPose(_ image: MImage) {
        detectPose(image.texture)
    }

    /// ハンドポーズ推定（非同期）
    public func detectHandPose(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var poses: [MLPose] = []
                for obs in (request.results ?? []) {
                    var landmarks: [MLLandmark] = []
                    if let points = try? obs.recognizedPoints(.all) {
                        for (key, point) in points {
                            let name = "\(key.rawValue)"
                            let lm = MLLandmark(
                                name: name,
                                x: Float(point.location.x) * imageWidth,
                                y: (1 - Float(point.location.y)) * imageHeight,
                                confidence: Float(point.confidence)
                            )
                            landmarks.append(lm)
                        }
                    }
                    poses.append(MLPose(landmarks: landmarks, confidence: obs.confidence))
                }

                buffer.store(.poses(poses, elapsed))
            } catch {
                print("[metaphor] Vision hand pose error: \(error)")
                buffer.store(.poses([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でハンドポーズ推定
    public func detectHandPose(_ image: MImage) {
        detectHandPose(image.texture)
    }

    // MARK: - Person Segmentation

    /// 人物セグメンテーション（非同期）
    public func segmentPerson(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first {
                    let maskBuffer = result.pixelBuffer
                    let maskWidth = CVPixelBufferGetWidth(maskBuffer)
                    let maskHeight = CVPixelBufferGetHeight(maskBuffer)
                    let floatData = extractFloatMaskData(from: maskBuffer)

                    let mask = MLSegmentMask(width: maskWidth, height: maskHeight, data: floatData)
                    buffer.store(.segmentMask(mask, maskBuffer, elapsed))
                } else {
                    buffer.store(.segmentMask(MLSegmentMask(width: 0, height: 0, data: []), nil, CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision segmentation error: \(error)")
                buffer.store(.segmentMask(MLSegmentMask(width: 0, height: 0, data: []), nil, CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でセグメンテーション
    public func segmentPerson(_ image: MImage) {
        segmentPerson(image.texture)
    }

    // MARK: - Text Recognition

    /// テキスト認識 / OCR（非同期）
    public func recognizeText(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let level = textRecognitionLevel
        let languages = textRecognitionLanguages
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.recognitionLanguages = languages

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                let texts = (request.results ?? []).compactMap { obs -> MLText? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let bb = obs.boundingBox
                    return MLText(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        x: Float(bb.origin.x) * imageWidth,
                        y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                        w: Float(bb.size.width) * imageWidth,
                        h: Float(bb.size.height) * imageHeight
                    )
                }

                buffer.store(.texts(texts, elapsed))
            } catch {
                print("[metaphor] Vision text recognition error: \(error)")
                buffer.store(.texts([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でテキスト認識
    public func recognizeText(_ image: MImage) {
        recognizeText(image.texture)
    }

    // MARK: - Face Detection

    /// 顔検出（非同期）
    public func detectFaces(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let withLandmarks = detectFaceLandmarks
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

            if withLandmarks {
                let request = VNDetectFaceLandmarksRequest()
                do {
                    try handler.perform([request])
                    let elapsed = CACurrentMediaTime() - startTime

                    let faces = (request.results ?? []).map { obs -> MLFace in
                        let bb = obs.boundingBox
                        var landmarks: [MLLandmark] = []

                        if let faceLandmarks = obs.landmarks {
                            let regions: [(String, VNFaceLandmarkRegion2D?)] = [
                                ("leftEye", faceLandmarks.leftEye),
                                ("rightEye", faceLandmarks.rightEye),
                                ("nose", faceLandmarks.nose),
                                ("outerLips", faceLandmarks.outerLips),
                                ("leftEyebrow", faceLandmarks.leftEyebrow),
                                ("rightEyebrow", faceLandmarks.rightEyebrow),
                            ]

                            for (name, region) in regions {
                                guard let region = region else { continue }
                                let points = region.normalizedPoints
                                if let center = points.first {
                                    let px = (Float(bb.origin.x) + Float(center.x) * Float(bb.size.width)) * imageWidth
                                    let py = (1 - Float(bb.origin.y) - Float(center.y) * Float(bb.size.height)) * imageHeight
                                    landmarks.append(MLLandmark(name: name, x: px, y: py, confidence: obs.confidence))
                                }
                            }
                        }

                        return MLFace(
                            x: Float(bb.origin.x) * imageWidth,
                            y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                            w: Float(bb.size.width) * imageWidth,
                            h: Float(bb.size.height) * imageHeight,
                            landmarks: landmarks
                        )
                    }

                    buffer.store(.faces(faces, elapsed))
                } catch {
                    print("[metaphor] Vision face detection error: \(error)")
                    buffer.store(.faces([], CACurrentMediaTime() - startTime))
                }
            } else {
                let request = VNDetectFaceRectanglesRequest()
                do {
                    try handler.perform([request])
                    let elapsed = CACurrentMediaTime() - startTime

                    let faces = (request.results ?? []).map { obs -> MLFace in
                        let bb = obs.boundingBox
                        return MLFace(
                            x: Float(bb.origin.x) * imageWidth,
                            y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                            w: Float(bb.size.width) * imageWidth,
                            h: Float(bb.size.height) * imageHeight,
                            landmarks: []
                        )
                    }

                    buffer.store(.faces(faces, elapsed))
                } catch {
                    print("[metaphor] Vision face detection error: \(error)")
                    buffer.store(.faces([], CACurrentMediaTime() - startTime))
                }
            }
        }
    }

    /// MImage で顔検出
    public func detectFaces(_ image: MImage) {
        detectFaces(image.texture)
    }

    // MARK: - Saliency

    /// サリエンシー種別
    public enum SaliencyType {
        case attention
        case objectness
    }

    /// サリエンシー検出（非同期）
    public func detectSaliency(_ texture: MTLTexture, type: SaliencyType = .attention) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request: VNImageBasedRequest
            switch type {
            case .attention:
                request = VNGenerateAttentionBasedSaliencyImageRequest()
            case .objectness:
                request = VNGenerateObjectnessBasedSaliencyImageRequest()
            }

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first as? VNSaliencyImageObservation {
                    let maskBuffer = result.pixelBuffer
                    let maskWidth = CVPixelBufferGetWidth(maskBuffer)
                    let maskHeight = CVPixelBufferGetHeight(maskBuffer)
                    let floatData = extractFloatMaskData(from: maskBuffer)

                    let sal = MLSaliency(width: maskWidth, height: maskHeight, data: floatData)
                    buffer.store(.saliency(sal, elapsed))
                } else {
                    buffer.store(.saliency(MLSaliency(width: 0, height: 0, data: []), CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision saliency error: \(error)")
                buffer.store(.saliency(MLSaliency(width: 0, height: 0, data: []), CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でサリエンシー検出
    public func detectSaliency(_ image: MImage, type: SaliencyType = .attention) {
        detectSaliency(image.texture, type: type)
    }

    // MARK: - Barcode / QR Detection

    /// バーコード/QR コード検出（非同期）
    public func detectBarcodes(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectBarcodesRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                let barcodes = (request.results ?? []).compactMap { obs -> MLBarcode? in
                    guard let payload = obs.payloadStringValue else { return nil }
                    let bb = obs.boundingBox
                    return MLBarcode(
                        payload: payload,
                        symbology: obs.symbology.rawValue,
                        x: Float(bb.origin.x) * imageWidth,
                        y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                        w: Float(bb.size.width) * imageWidth,
                        h: Float(bb.size.height) * imageHeight
                    )
                }

                buffer.store(.barcodes(barcodes, elapsed))
            } catch {
                print("[metaphor] Vision barcode detection error: \(error)")
                buffer.store(.barcodes([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でバーコード検出
    public func detectBarcodes(_ image: MImage) {
        detectBarcodes(image.texture)
    }

    // MARK: - Contour Detection

    /// 輪郭検出（非同期）
    public func detectContours(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectContoursRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var mlContours: [MLContour] = []
                if let result = request.results?.first {
                    let topLevel = result.topLevelContours
                    for contour in topLevel {
                        let points = contour.normalizedPoints.map { point -> SIMD2<Float> in
                            SIMD2<Float>(
                                Float(point.x) * imageWidth,
                                (1 - Float(point.y)) * imageHeight
                            )
                        }
                        let childIndices = (0..<contour.childContourCount).map { $0 }
                        mlContours.append(MLContour(points: points, childIndices: childIndices))
                    }
                }

                buffer.store(.contours(mlContours, elapsed))
            } catch {
                print("[metaphor] Vision contour detection error: \(error)")
                buffer.store(.contours([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で輪郭検出
    public func detectContours(_ image: MImage) {
        detectContours(image.texture)
    }

    // MARK: - Custom Model Inference via Vision

    /// カスタム CoreML モデルで Vision 推論（非同期）
    /// 結果はモデルの出力型に応じて classifications / detections / segmentMask に格納される
    public func predict(_ texture: MTLTexture) {
        guard !isProcessing, let model = customModel else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let threshold = confidenceThreshold
        let maxCls = maxClassifications
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                guard let results = request.results else {
                    buffer.store(.classifications([], elapsed))
                    return
                }

                if let firstResult = results.first {
                    if firstResult is VNClassificationObservation {
                        let cls = (results as? [VNClassificationObservation] ?? [])
                            .sorted { $0.confidence > $1.confidence }
                            .prefix(maxCls)
                            .map { MLClassification(label: $0.identifier, confidence: $0.confidence) }
                        buffer.store(.classifications(Array(cls), elapsed))
                    } else if firstResult is VNRecognizedObjectObservation {
                        let dets = (results as? [VNRecognizedObjectObservation] ?? [])
                            .filter { $0.confidence >= threshold }
                            .map { obs -> MLDetection in
                                let bb = obs.boundingBox
                                return MLDetection(
                                    label: obs.labels.first?.identifier ?? "unknown",
                                    confidence: obs.confidence,
                                    x: Float(bb.origin.x) * imageWidth,
                                    y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                                    w: Float(bb.size.width) * imageWidth,
                                    h: Float(bb.size.height) * imageHeight
                                )
                            }
                        buffer.store(.detections(dets, elapsed))
                    } else if let pixelObs = firstResult as? VNPixelBufferObservation {
                        let maskBuffer = pixelObs.pixelBuffer
                        let maskWidth = CVPixelBufferGetWidth(maskBuffer)
                        let maskHeight = CVPixelBufferGetHeight(maskBuffer)
                        let mask = MLSegmentMask(width: maskWidth, height: maskHeight, data: [])
                        buffer.store(.segmentMask(mask, maskBuffer, elapsed))
                    } else {
                        buffer.store(.classifications([], elapsed))
                    }
                }
            } catch {
                print("[metaphor] Vision custom model error: \(error)")
                buffer.store(.classifications([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でカスタムモデル推論
    public func predict(_ image: MImage) {
        predict(image.texture)
    }

    // MARK: - 3D Body Pose Estimation

    /// 3Dボディポーズ推定（非同期）
    /// カメラ空間でのメートル単位の3D関節位置を取得
    public func detectPose3D(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectHumanBodyPose3DRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var poses3D: [MLPose3D] = []
                for obs in (request.results ?? []) {
                    var landmarks: [MLLandmark3D] = []
                    let jointNames: [VNHumanBodyPose3DObservation.JointName] = [
                        .root, .centerHead, .centerShoulder,
                        .leftShoulder, .leftElbow, .leftWrist,
                        .rightShoulder, .rightElbow, .rightWrist,
                        .leftHip, .leftKnee, .leftAnkle,
                        .rightHip, .rightKnee, .rightAnkle,
                        .spine
                    ]

                    for jointName in jointNames {
                        if let point = try? obs.recognizedPoint(jointName) {
                            let pos = point.position
                            landmarks.append(MLLandmark3D(
                                name: "\(jointName.rawValue.rawValue)",
                                x: pos.columns.3.x,
                                y: pos.columns.3.y,
                                z: pos.columns.3.z,
                                confidence: 1.0,
                                localPosition: point.localPosition
                            ))
                        }
                    }

                    let bodyHeight = Float(obs.bodyHeight)
                    poses3D.append(MLPose3D(landmarks: landmarks, confidence: 1.0, bodyHeight: bodyHeight))
                }

                buffer.store(.poses3D(poses3D, elapsed))
            } catch {
                print("[metaphor] Vision 3D pose error: \(error)")
                buffer.store(.poses3D([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で3Dポーズ推定
    public func detectPose3D(_ image: MImage) {
        detectPose3D(image.texture)
    }

    // MARK: - Animal Recognition

    /// 動物認識（非同期）— 猫/犬を検出
    public func detectAnimals(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let threshold = confidenceThreshold
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNRecognizeAnimalsRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var detections: [MLDetection] = []
                for obs in (request.results ?? []) {
                    guard obs.confidence >= threshold else { continue }
                    let bb = obs.boundingBox
                    let label = obs.labels.first?.identifier ?? "animal"
                    detections.append(MLDetection(
                        label: label,
                        confidence: obs.confidence,
                        x: Float(bb.origin.x) * imageWidth,
                        y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                        w: Float(bb.size.width) * imageWidth,
                        h: Float(bb.size.height) * imageHeight
                    ))
                }

                buffer.store(.animalDetections(detections, elapsed))
            } catch {
                print("[metaphor] Vision animal recognition error: \(error)")
                buffer.store(.animalDetections([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で動物認識
    public func detectAnimals(_ image: MImage) {
        detectAnimals(image.texture)
    }

    // MARK: - Animal Body Pose

    /// 動物ポーズ推定（非同期）— 猫/犬の25関節を検出
    public func detectAnimalPose(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectAnimalBodyPoseRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var poses: [MLPose] = []
                for obs in (request.results ?? []) {
                    var landmarks: [MLLandmark] = []
                    if let points = try? obs.recognizedPoints(.all) {
                        for (key, point) in points {
                            let lm = MLLandmark(
                                name: "\(key.rawValue)",
                                x: Float(point.location.x) * imageWidth,
                                y: (1 - Float(point.location.y)) * imageHeight,
                                confidence: Float(point.confidence)
                            )
                            landmarks.append(lm)
                        }
                    }
                    poses.append(MLPose(landmarks: landmarks, confidence: obs.confidence))
                }

                buffer.store(.animalPoses(poses, elapsed))
            } catch {
                print("[metaphor] Vision animal pose error: \(error)")
                buffer.store(.animalPoses([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で動物ポーズ推定
    public func detectAnimalPose(_ image: MImage) {
        detectAnimalPose(image.texture)
    }

    // MARK: - Human Rectangle Detection

    /// 人物矩形検出（非同期）— ポーズより軽量な人物検出
    public func detectHumanRectangles(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectHumanRectanglesRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var detections: [MLDetection] = []
                for obs in (request.results ?? []) {
                    let bb = obs.boundingBox
                    detections.append(MLDetection(
                        label: "human",
                        confidence: obs.confidence,
                        x: Float(bb.origin.x) * imageWidth,
                        y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imageHeight,
                        w: Float(bb.size.width) * imageWidth,
                        h: Float(bb.size.height) * imageHeight
                    ))
                }

                buffer.store(.humanRectangles(detections, elapsed))
            } catch {
                print("[metaphor] Vision human rectangle error: \(error)")
                buffer.store(.humanRectangles([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で人物矩形検出
    public func detectHumanRectangles(_ image: MImage) {
        detectHumanRectangles(image.texture)
    }

    // MARK: - Rectangle Detection

    /// 矩形検出（非同期）— 4コーナーの矩形を検出
    public func detectRectangles(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let minAspect = rectangleMinAspectRatio
        let maxAspect = rectangleMaxAspectRatio
        let minSize = rectangleMinSize
        let maxResults = maxRectangles
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imageWidth = Float(texture.width)
        let imageHeight = Float(texture.height)

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectRectanglesRequest()
            request.minimumAspectRatio = VNAspectRatio(minAspect)
            request.maximumAspectRatio = VNAspectRatio(maxAspect)
            request.minimumSize = minSize
            request.maximumObservations = maxResults

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                var rects: [MLRectangle] = []
                for obs in (request.results ?? []) {
                    func convert(_ p: CGPoint) -> SIMD2<Float> {
                        SIMD2<Float>(Float(p.x) * imageWidth, (1 - Float(p.y)) * imageHeight)
                    }
                    rects.append(MLRectangle(
                        topLeft: convert(obs.topLeft),
                        topRight: convert(obs.topRight),
                        bottomRight: convert(obs.bottomRight),
                        bottomLeft: convert(obs.bottomLeft),
                        confidence: obs.confidence
                    ))
                }

                buffer.store(.rectangles(rects, elapsed))
            } catch {
                print("[metaphor] Vision rectangle detection error: \(error)")
                buffer.store(.rectangles([], CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で矩形検出
    public func detectRectangles(_ image: MImage) {
        detectRectangles(image.texture)
    }

    // MARK: - Image Feature Print

    /// 画像特徴ベクトルを生成（非同期）
    /// 類似画像検索やコンテンツ比較に使用
    public func generateFeaturePrint(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNGenerateImageFeaturePrintRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first {
                    let count = result.elementCount
                    var floatData = [Float](repeating: 0, count: count)

                    let elementType: String
                    switch result.elementType {
                    case .float:
                        elementType = "float"
                        result.data.withUnsafeBytes { ptr in
                            guard let baseAddr = ptr.baseAddress else { return }
                            let floatPtr = baseAddr.assumingMemoryBound(to: Float.self)
                            for i in 0..<count {
                                floatData[i] = floatPtr[i]
                            }
                        }
                    case .double:
                        elementType = "double"
                        result.data.withUnsafeBytes { ptr in
                            guard let baseAddr = ptr.baseAddress else { return }
                            let doublePtr = baseAddr.assumingMemoryBound(to: Double.self)
                            for i in 0..<count {
                                floatData[i] = Float(doublePtr[i])
                            }
                        }
                    @unknown default:
                        elementType = "unknown"
                    }

                    let fp = MLFeaturePrint(data: floatData, elementType: elementType)
                    buffer.store(.featurePrint(fp, elapsed))
                } else {
                    buffer.store(.featurePrint(MLFeaturePrint(data: []), CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision feature print error: \(error)")
                buffer.store(.featurePrint(MLFeaturePrint(data: []), CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で特徴ベクトル生成
    public func generateFeaturePrint(_ image: MImage) {
        generateFeaturePrint(image.texture)
    }

    // MARK: - Foreground Instance Mask

    /// 前景インスタンスマスク生成（非同期）
    /// 人物以外も含む前景オブジェクトを個別にセグメンテーション
    public func segmentForeground(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first {
                    let allInstances = result.allInstances
                    let instanceCount = allInstances.count

                    let combinedMaskBuffer = try result.generateMaskedImage(
                        ofInstances: allInstances,
                        from: handler,
                        croppedToInstancesExtent: false
                    )
                    let combinedData = extractFloatMaskData(from: combinedMaskBuffer)
                    let maskWidth = CVPixelBufferGetWidth(combinedMaskBuffer)
                    let maskHeight = CVPixelBufferGetHeight(combinedMaskBuffer)

                    var instanceMasks: [[Float]] = []
                    for instance in allInstances {
                        let indexSet = IndexSet(integer: instance)
                        if let singleMask = try? result.generateMaskedImage(
                            ofInstances: indexSet,
                            from: handler,
                            croppedToInstancesExtent: false
                        ) {
                            instanceMasks.append(extractFloatMaskData(from: singleMask))
                        }
                    }

                    let mask = MLInstanceMask(
                        width: maskWidth, height: maskHeight,
                        instanceCount: instanceCount,
                        instanceMasks: instanceMasks,
                        combinedMask: combinedData
                    )
                    buffer.store(.foregroundInstanceMask(mask, combinedMaskBuffer, elapsed))
                } else {
                    let empty = MLInstanceMask(width: 0, height: 0, instanceCount: 0, instanceMasks: [], combinedMask: [])
                    buffer.store(.foregroundInstanceMask(empty, nil, CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision foreground instance mask error: \(error)")
                let empty = MLInstanceMask(width: 0, height: 0, instanceCount: 0, instanceMasks: [], combinedMask: [])
                buffer.store(.foregroundInstanceMask(empty, nil, CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で前景マスク生成
    public func segmentForeground(_ image: MImage) {
        segmentForeground(image.texture)
    }

    // MARK: - Person Instance Mask

    /// 人物インスタンスマスク生成（非同期）
    /// 各人物を個別にセグメンテーション
    public func segmentPersonInstances(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNGeneratePersonInstanceMaskRequest()

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first {
                    let allInstances = result.allInstances
                    let instanceCount = allInstances.count

                    let combinedMaskBuffer = try result.generateMaskedImage(
                        ofInstances: allInstances,
                        from: handler,
                        croppedToInstancesExtent: false
                    )
                    let combinedData = extractFloatMaskData(from: combinedMaskBuffer)
                    let maskWidth = CVPixelBufferGetWidth(combinedMaskBuffer)
                    let maskHeight = CVPixelBufferGetHeight(combinedMaskBuffer)

                    var instanceMasks: [[Float]] = []
                    for instance in allInstances {
                        let indexSet = IndexSet(integer: instance)
                        if let singleMask = try? result.generateMaskedImage(
                            ofInstances: indexSet,
                            from: handler,
                            croppedToInstancesExtent: false
                        ) {
                            instanceMasks.append(extractFloatMaskData(from: singleMask))
                        }
                    }

                    let mask = MLInstanceMask(
                        width: maskWidth, height: maskHeight,
                        instanceCount: instanceCount,
                        instanceMasks: instanceMasks,
                        combinedMask: combinedData
                    )
                    buffer.store(.personInstanceMask(mask, combinedMaskBuffer, elapsed))
                } else {
                    let empty = MLInstanceMask(width: 0, height: 0, instanceCount: 0, instanceMasks: [], combinedMask: [])
                    buffer.store(.personInstanceMask(empty, nil, CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision person instance mask error: \(error)")
                let empty = MLInstanceMask(width: 0, height: 0, instanceCount: 0, instanceMasks: [], combinedMask: [])
                buffer.store(.personInstanceMask(empty, nil, CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage で人物インスタンスマスク生成
    public func segmentPersonInstances(_ image: MImage) {
        segmentPersonInstances(image.texture)
    }

    // MARK: - Object Tracking

    /// オブジェクトトラッキングを開始
    /// - Parameters:
    ///   - x: バウンディングボックス x（ピクセル座標、左上原点）
    ///   - y: バウンディングボックス y
    ///   - w: バウンディングボックス幅
    ///   - h: バウンディングボックス高さ
    ///   - imageWidth: 画像の幅
    ///   - imageHeight: 画像の高さ
    public func startTracking(x: Float, y: Float, w: Float, h: Float, imageWidth: Float, imageHeight: Float) {
        // ピクセル座標（左上原点）→ 正規化座標（左下原点）
        let normX = CGFloat(x / imageWidth)
        let normY = CGFloat(1.0 - (y + h) / imageHeight)
        let normW = CGFloat(w / imageWidth)
        let normH = CGFloat(h / imageHeight)
        let boundingBox = CGRect(x: normX, y: normY, width: normW, height: normH)

        let observation = VNDetectedObjectObservation(boundingBox: boundingBox)
        trackingState.setObservation(observation)
        trackingSequenceHandler = VNSequenceRequestHandler()
        trackingImageWidth = imageWidth
        trackingImageHeight = imageHeight
        isTracking = true
        trackingState.setProcessing(false)
    }

    /// 毎フレームのトラッキング更新（非同期）
    public func trackObject(_ texture: MTLTexture) {
        guard isTracking, !trackingState.getProcessing() else { return }
        guard let prevObservation = trackingState.getObservation() else { return }
        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        trackingState.setProcessing(true)

        let seqHandler = trackingSequenceHandler ?? VNSequenceRequestHandler()
        let confThreshold = trackingConfidenceThreshold
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()
        let imgW = trackingImageWidth
        let imgH = trackingImageHeight
        let state = trackingState

        inferenceQueue.async {
            let request = VNTrackObjectRequest(detectedObjectObservation: prevObservation)
            request.trackingLevel = .accurate

            do {
                try seqHandler.perform([request], on: pixelBuffer)
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first as? VNDetectedObjectObservation {
                    let bb = result.boundingBox
                    let tracked = MLTrackedObject(
                        x: Float(bb.origin.x) * imgW,
                        y: (1 - Float(bb.origin.y) - Float(bb.size.height)) * imgH,
                        w: Float(bb.size.width) * imgW,
                        h: Float(bb.size.height) * imgH,
                        confidence: result.confidence,
                        isTracking: result.confidence >= confThreshold
                    )

                    state.setObservation(result)
                    buffer.store(.trackedObject(tracked, elapsed))
                } else {
                    let failed = MLTrackedObject(x: 0, y: 0, w: 0, h: 0, confidence: 0, isTracking: false)
                    buffer.store(.trackedObject(failed, CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision tracking error: \(error)")
                let failed = MLTrackedObject(x: 0, y: 0, w: 0, h: 0, confidence: 0, isTracking: false)
                buffer.store(.trackedObject(failed, CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でトラッキング
    public func trackObject(_ image: MImage) {
        trackObject(image.texture)
    }

    /// トラッキングを停止
    public func stopTracking() {
        isTracking = false
        trackingState.setProcessing(false)
        trackingState.setObservation(nil)
        trackingSequenceHandler = nil
        trackedObject = nil
    }

    // MARK: - Optical Flow

    /// オプティカルフロー計算（非同期）
    /// 前フレームと現フレーム間のピクセル単位の動きベクトルを計算
    public func computeOpticalFlow(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        guard let currentPixelBuffer = converter.pixelBuffer(from: texture) else { return }

        guard let prevBuffer = previousFramePixelBuffer else {
            previousFramePixelBuffer = currentPixelBuffer
            return
        }

        isProcessing = true
        previousFramePixelBuffer = currentPixelBuffer

        let accuracy = opticalFlowAccuracy
        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: prevBuffer, options: [:])
            let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: currentPixelBuffer)
            request.computationAccuracy = accuracy

            do {
                try handler.perform([request])
                let elapsed = CACurrentMediaTime() - startTime

                if let result = request.results?.first {
                    let flowBuffer = result.pixelBuffer
                    let flowWidth = CVPixelBufferGetWidth(flowBuffer)
                    let flowHeight = CVPixelBufferGetHeight(flowBuffer)

                    CVPixelBufferLockBaseAddress(flowBuffer, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(flowBuffer, .readOnly) }

                    var flowData = [Float](repeating: 0, count: flowWidth * flowHeight * 2)

                    if let baseAddress = CVPixelBufferGetBaseAddress(flowBuffer) {
                        let bytesPerRow = CVPixelBufferGetBytesPerRow(flowBuffer)
                        for y in 0..<flowHeight {
                            let row = baseAddress.advanced(by: y * bytesPerRow)
                                .assumingMemoryBound(to: Float.self)
                            for x in 0..<flowWidth {
                                let srcIdx = x * 2
                                let dstIdx = (y * flowWidth + x) * 2
                                flowData[dstIdx] = row[srcIdx]
                                flowData[dstIdx + 1] = row[srcIdx + 1]
                            }
                        }
                    }

                    let flow = MLOpticalFlow(width: flowWidth, height: flowHeight, data: flowData)
                    buffer.store(.opticalFlow(flow, flowBuffer, elapsed))
                } else {
                    buffer.store(.opticalFlow(MLOpticalFlow(width: 0, height: 0, data: []), nil, CACurrentMediaTime() - startTime))
                }
            } catch {
                print("[metaphor] Vision optical flow error: \(error)")
                buffer.store(.opticalFlow(MLOpticalFlow(width: 0, height: 0, data: []), nil, CACurrentMediaTime() - startTime))
            }
        }
    }

    /// MImage でオプティカルフロー計算
    public func computeOpticalFlow(_ image: MImage) {
        computeOpticalFlow(image.texture)
    }

    /// オプティカルフローの前フレームバッファをリセット
    public func resetOpticalFlow() {
        previousFramePixelBuffer = nil
        opticalFlow = nil
        opticalFlowTexture = nil
    }
}
