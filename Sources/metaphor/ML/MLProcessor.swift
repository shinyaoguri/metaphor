import CoreML
import CoreVideo
import Metal
import QuartzCore

// MARK: - Thread-safe Result Buffer

private enum MLResultValue {
    case image(CVPixelBuffer, inferenceTime: Double)
    case generic(MLFeatureProvider, inferenceTime: Double)
}

private final class MLResultBuffer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _result: MLResultValue?
    private nonisolated(unsafe) var _isComplete = false

    func storeImageResult(_ pixelBuffer: CVPixelBuffer, inferenceTime: Double) {
        lock.lock()
        _result = .image(pixelBuffer, inferenceTime: inferenceTime)
        _isComplete = true
        lock.unlock()
    }

    func storeGenericResult(_ provider: MLFeatureProvider, inferenceTime: Double) {
        lock.lock()
        _result = .generic(provider, inferenceTime: inferenceTime)
        _isComplete = true
        lock.unlock()
    }

    func take() -> MLResultValue? {
        lock.lock()
        guard _isComplete else {
            lock.unlock()
            return nil
        }
        let r = _result
        _result = nil
        _isComplete = false
        lock.unlock()
        return r
    }
}

// MARK: - MLProcessor

/// CoreML モデルラッパー
///
/// .mlmodelc / .mlpackage / .mlmodel ファイルを読み込み、
/// テクスチャや MLMultiArray を入力として推論を実行する。
/// 非同期推論をサポートし、draw loop をブロックしない。
///
/// ```swift
/// var ml: MLProcessor!
/// func setup() {
///     ml = try! loadMLModel("style_transfer.mlmodelc")
/// }
/// func draw() {
///     ml.update()
///     if let result = ml.outputTexture {
///         image(result, 0, 0, width, height)
///     }
/// }
/// ```
@MainActor
public final class MLProcessor {

    // MARK: - Public Properties

    /// モデルが読み込み済みかどうか
    public private(set) var isLoaded: Bool = false

    /// 推論実行中かどうか
    public private(set) var isProcessing: Bool = false

    /// 最後の推論にかかった時間（秒）
    public private(set) var inferenceTime: Double = 0

    /// モデルの説明（メタデータ）
    public var modelDescription: String? {
        coreMLModel?.modelDescription.metadata[.description] as? String
    }

    /// 出力テクスチャ（image-to-image モデル用、update() 後に有効）
    public private(set) var outputTexture: MImage?

    /// 出力 MLMultiArray（汎用モデル用）
    public private(set) var outputMultiArray: MLMultiArray?

    /// 出力分類結果
    public private(set) var outputClassifications: [MLClassification] = []

    /// 出力辞書（dict 型出力）
    public private(set) var outputDictionary: [String: Double]?

    // MARK: - Configuration

    /// コンピュートユニット設定
    public var computeUnit: MLComputeUnit = .all

    // MARK: - Private

    private var coreMLModel: CoreML.MLModel?
    private let device: MTLDevice
    private let converter: MLTextureConverter
    private let resultBuffer = MLResultBuffer()
    private let inferenceQueue = DispatchQueue(label: "metaphor.ml.inference", qos: .userInitiated)

    // MARK: - Initialization

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.converter = MLTextureConverter(device: device, commandQueue: commandQueue)
    }

    // MARK: - Loading

    /// モデルファイルを読み込む
    /// - Parameter path: .mlmodelc / .mlpackage / .mlmodel ファイルパス
    public func load(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MLError.modelNotFound(path)
        }

        let config = MLModelConfiguration()
        config.computeUnits = computeUnit.coreMLUnit

        do {
            coreMLModel = try CoreML.MLModel(contentsOf: url, configuration: config)
            isLoaded = true
        } catch {
            throw MLError.modelLoadFailed(path, underlying: error)
        }
    }

    /// バンドルリソースからモデルを読み込む
    public func load(named name: String, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "mlmodelc")
                ?? bundle.url(forResource: name, withExtension: "mlpackage") else {
            throw MLError.modelNotFound(name)
        }

        let config = MLModelConfiguration()
        config.computeUnits = computeUnit.coreMLUnit

        do {
            coreMLModel = try CoreML.MLModel(contentsOf: url, configuration: config)
            isLoaded = true
        } catch {
            throw MLError.modelLoadFailed(name, underlying: error)
        }
    }

    /// 非同期でモデルを読み込む（大きなモデル用）
    public func loadAsync(_ path: String, completion: @escaping @MainActor (Error?) -> Void) {
        let computeUnit = self.computeUnit
        inferenceQueue.async { [weak self] in
            let url = URL(fileURLWithPath: path)
            let config = MLModelConfiguration()
            config.computeUnits = computeUnit.coreMLUnit

            do {
                let model = try CoreML.MLModel(contentsOf: url, configuration: config)
                DispatchQueue.main.async {
                    self?.coreMLModel = model
                    self?.isLoaded = true
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(MLError.modelLoadFailed(path, underlying: error))
                }
            }
        }
    }

    // MARK: - Inference (Texture -> Texture)

    /// テクスチャを入力として非同期推論（image-to-image）
    /// 結果は次の update() で outputTexture に反映される
    public func predict(texture: MTLTexture) {
        guard isLoaded, !isProcessing, let capturedModel = coreMLModel else { return }

        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            do {
                let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
                // 画像入力名をモデル定義から自動検出
                let inputName = capturedModel.modelDescription.inputDescriptionsByName.first(
                    where: { $0.value.type == .image }
                )?.key ?? "image"

                let provider = try MLDictionaryFeatureProvider(
                    dictionary: [inputName: featureValue]
                )
                let result = try capturedModel.prediction(from: provider)

                let elapsed = CACurrentMediaTime() - startTime

                // 画像型出力を検索
                let outputName = capturedModel.modelDescription.outputDescriptionsByName.first(
                    where: { $0.value.type == .image }
                )?.key

                if let outputName,
                   let outputValue = result.featureValue(for: outputName),
                   let outputPB = outputValue.imageBufferValue {
                    buffer.storeImageResult(outputPB, inferenceTime: elapsed)
                } else {
                    buffer.storeGenericResult(result, inferenceTime: elapsed)
                }
            } catch {
                print("[metaphor] ML inference error: \(error)")
            }
        }
    }

    /// MImage を入力として非同期推論
    public func predict(image: MImage) {
        predict(texture: image.texture)
    }

    // MARK: - Inference (Generic)

    /// 汎用入力で非同期推論
    public func predict(inputs: [String: MLFeatureValue]) {
        guard isLoaded, !isProcessing, let capturedModel = coreMLModel else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            do {
                let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
                let result = try capturedModel.prediction(from: provider)
                let elapsed = CACurrentMediaTime() - startTime
                buffer.storeGenericResult(result, inferenceTime: elapsed)
            } catch {
                print("[metaphor] ML inference error: \(error)")
            }
        }
    }

    // MARK: - Synchronous Inference

    /// 同期推論（小さなモデル向け、draw loop をブロックする）
    public func predictSync(texture: MTLTexture) throws {
        guard isLoaded, let capturedModel = coreMLModel else {
            throw MLError.inferenceFailed("Model not loaded")
        }

        guard let pixelBuffer = converter.pixelBuffer(from: texture) else {
            throw MLError.textureConversionFailed("Failed to create CVPixelBuffer from texture")
        }

        let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
        let inputName = capturedModel.modelDescription.inputDescriptionsByName.first(
            where: { $0.value.type == .image }
        )?.key ?? "image"

        let provider = try MLDictionaryFeatureProvider(
            dictionary: [inputName: featureValue]
        )
        let startTime = CACurrentMediaTime()
        let result = try capturedModel.prediction(from: provider)
        inferenceTime = CACurrentMediaTime() - startTime

        let outputName = capturedModel.modelDescription.outputDescriptionsByName.first(
            where: { $0.value.type == .image }
        )?.key

        if let outputName,
           let outputValue = result.featureValue(for: outputName),
           let outputPB = outputValue.imageBufferValue {
            if let tex = converter.texture(from: outputPB) {
                outputTexture = MImage(texture: tex)
            }
        } else {
            parseGenericOutput(result)
        }
    }

    // MARK: - Update (per-frame)

    /// 毎フレーム呼ぶ更新メソッド（draw() の先頭で呼ぶ）
    /// 非同期推論の結果を公開プロパティに反映する
    public func update() {
        guard let result = resultBuffer.take() else { return }
        isProcessing = false

        switch result {
        case .image(let pixelBuffer, let time):
            inferenceTime = time
            if let tex = converter.texture(from: pixelBuffer) {
                outputTexture = MImage(texture: tex)
            }

        case .generic(let featureProvider, let time):
            inferenceTime = time
            parseGenericOutput(featureProvider)
        }
    }

    private func parseGenericOutput(_ provider: MLFeatureProvider) {
        for name in provider.featureNames {
            guard let value = provider.featureValue(for: name) else { continue }
            switch value.type {
            case .multiArray:
                outputMultiArray = value.multiArrayValue
            case .dictionary:
                if let dict = value.dictionaryValue as? [String: NSNumber] {
                    outputDictionary = dict.mapValues { $0.doubleValue }
                }
            case .string:
                let str: String = value.stringValue
                outputClassifications = [MLClassification(label: str, confidence: 1.0)]
            default:
                break
            }
        }
    }

    // MARK: - Metadata

    /// モデルの入力名・型一覧
    public var inputDescriptions: [(name: String, type: String)] {
        guard let model = coreMLModel else { return [] }
        return model.modelDescription.inputDescriptionsByName.map {
            (name: $0.key, type: "\($0.value.type)")
        }
    }

    /// モデルの出力名・型一覧
    public var outputDescriptions: [(name: String, type: String)] {
        guard let model = coreMLModel else { return [] }
        return model.modelDescription.outputDescriptionsByName.map {
            (name: $0.key, type: "\($0.value.type)")
        }
    }

    /// 内部の CoreML.MLModel へのアクセス（上級者向け）
    public var rawModel: CoreML.MLModel? { coreMLModel }
}
