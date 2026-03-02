import CoreML
import Metal

/// Wrap an image-to-image CoreML model for style transfer.
///
/// Provide a thin convenience layer over MLProcessor tailored for
/// style transfer and image transformation models.
///
/// ```swift
/// var style: MLStyleTransfer!
/// func setup() {
///     style = try! loadStyleTransfer("starry_night.mlmodelc")
/// }
/// func draw() {
///     style.update()
///     cam.read()
///     if let tex = cam.texture { style.apply(tex) }
///     if let result = style.outputTexture {
///         image(result, 0, 0, width, height)
///     }
/// }
/// ```
@MainActor
public final class MLStyleTransfer {

    // MARK: - Public Properties

    /// Store the output texture (available after `apply()` + `update()`).
    public private(set) var outputTexture: MImage?

    /// Indicate whether an inference request is in progress.
    public private(set) var isProcessing: Bool = false

    /// Store the elapsed time in seconds for the last inference.
    public private(set) var inferenceTime: Double = 0

    /// Indicate whether the model has been loaded.
    public var isLoaded: Bool { model.isLoaded }

    // MARK: - Private

    private let model: MLProcessor

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.model = MLProcessor(device: device, commandQueue: commandQueue)
    }

    // MARK: - Loading

    /// Load a style transfer model from a file path.
    /// - Parameters:
    ///   - path: Path to a .mlmodelc, .mlpackage, or .mlmodel file.
    ///   - computeUnit: The compute unit preference for inference.
    /// - Throws: ``MLError`` if the file is not found or loading fails.
    public func load(_ path: String, computeUnit: MLComputeUnit = .all) throws {
        model.computeUnit = computeUnit
        try model.load(path)
    }

    /// Load a style transfer model from a bundle resource.
    /// - Parameters:
    ///   - name: The resource name without extension.
    ///   - computeUnit: The compute unit preference for inference.
    /// - Throws: ``MLError`` if the resource is not found or loading fails.
    public func load(named name: String, computeUnit: MLComputeUnit = .all) throws {
        model.computeUnit = computeUnit
        try model.load(named: name)
    }

    // MARK: - Apply

    /// Apply style transfer to a Metal texture asynchronously.
    /// - Parameter texture: The input texture to stylize.
    public func apply(_ texture: MTLTexture) {
        guard !isProcessing else { return }
        isProcessing = true
        model.predict(texture: texture)
    }

    /// Apply style transfer to an MImage asynchronously.
    /// - Parameter image: The input image to stylize.
    public func apply(_ image: MImage) {
        apply(image.texture)
    }

    // MARK: - Update

    /// Flush pending inference results into public properties.
    ///
    /// Call this every frame to receive the latest style transfer output.
    public func update() {
        model.update()
        if model.outputTexture != nil {
            outputTexture = model.outputTexture
            inferenceTime = model.inferenceTime
            isProcessing = false
        }
    }
}
