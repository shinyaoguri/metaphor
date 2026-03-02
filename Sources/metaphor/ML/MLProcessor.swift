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

/// Wrap a CoreML model for general-purpose inference.
///
/// Load .mlmodelc, .mlpackage, or .mlmodel files and run inference
/// using textures or MLMultiArray inputs. Supports asynchronous inference
/// so the draw loop is never blocked.
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

    /// Indicate whether the model has been loaded.
    public private(set) var isLoaded: Bool = false

    /// Indicate whether an inference request is in progress.
    public private(set) var isProcessing: Bool = false

    /// Store the elapsed time in seconds for the last inference.
    public private(set) var inferenceTime: Double = 0

    /// Return the model description metadata string, if available.
    public var modelDescription: String? {
        coreMLModel?.modelDescription.metadata[.description] as? String
    }

    /// Store the output texture for image-to-image models (available after `update()`).
    public private(set) var outputTexture: MImage?

    /// Store the output MLMultiArray for general-purpose models.
    public private(set) var outputMultiArray: MLMultiArray?

    /// Store the output classification results.
    public private(set) var outputClassifications: [MLClassification] = []

    /// Store the output dictionary for dict-type model outputs.
    public private(set) var outputDictionary: [String: Double]?

    // MARK: - Configuration

    /// Set the compute unit preference for inference.
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

    /// Load a model from a file path.
    /// - Parameter path: Path to a .mlmodelc, .mlpackage, or .mlmodel file.
    /// - Throws: ``MLError`` if the file is not found or loading fails.
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

    /// Load a model from a bundle resource.
    /// - Parameters:
    ///   - name: The resource name without extension.
    ///   - bundle: The bundle to search for the resource.
    /// - Throws: ``MLError`` if the resource is not found or loading fails.
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

    /// Load a model asynchronously (for large models).
    /// - Parameters:
    ///   - path: Path to the model file.
    ///   - completion: Called on the main thread when loading completes or fails.
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

    /// Run asynchronous inference with a texture input (image-to-image).
    ///
    /// The result becomes available via `outputTexture` after the next `update()` call.
    /// - Parameter texture: The input Metal texture.
    public func predict(texture: MTLTexture) {
        guard isLoaded, !isProcessing, let capturedModel = coreMLModel else { return }

        guard let pixelBuffer = converter.pixelBuffer(from: texture) else { return }
        isProcessing = true

        let buffer = resultBuffer
        let startTime = CACurrentMediaTime()

        inferenceQueue.async {
            do {
                let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
                // Auto-detect the image input name from the model definition
                let inputName = capturedModel.modelDescription.inputDescriptionsByName.first(
                    where: { $0.value.type == .image }
                )?.key ?? "image"

                let provider = try MLDictionaryFeatureProvider(
                    dictionary: [inputName: featureValue]
                )
                let result = try capturedModel.prediction(from: provider)

                let elapsed = CACurrentMediaTime() - startTime

                // Search for an image-type output
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

    /// Run asynchronous inference with an MImage input.
    /// - Parameter image: The input image.
    public func predict(image: MImage) {
        predict(texture: image.texture)
    }

    // MARK: - Inference (Generic)

    /// Run asynchronous inference with generic feature value inputs.
    /// - Parameter inputs: A dictionary mapping input names to MLFeatureValue instances.
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

    /// Run synchronous inference with a texture input (blocks the draw loop).
    ///
    /// Use this for small models where latency is acceptable.
    /// - Parameter texture: The input Metal texture.
    /// - Throws: ``MLError`` if the model is not loaded or inference fails.
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

    /// Flush pending asynchronous inference results into public properties.
    ///
    /// Call this at the beginning of every `draw()` frame.
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

    /// Return a list of the model's input names and types.
    public var inputDescriptions: [(name: String, type: String)] {
        guard let model = coreMLModel else { return [] }
        return model.modelDescription.inputDescriptionsByName.map {
            (name: $0.key, type: "\($0.value.type)")
        }
    }

    /// Return a list of the model's output names and types.
    public var outputDescriptions: [(name: String, type: String)] {
        guard let model = coreMLModel else { return [] }
        return model.modelDescription.outputDescriptionsByName.map {
            (name: $0.key, type: "\($0.value.type)")
        }
    }

    /// Access the underlying CoreML.MLModel instance (advanced use).
    public var rawModel: CoreML.MLModel? { coreMLModel }
}
