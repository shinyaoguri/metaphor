import MetaphorCore
import MetaphorCoreImage

// MARK: - CoreImage Filter Bridge

@MainActor
private var _ciWrapperStorage: [ObjectIdentifier: CIFilterWrapper] = [:]

extension SketchContext {
    /// The lazily initialized CoreImage filter wrapper (stored externally).
    var _ciFilterWrapper: CIFilterWrapper? {
        get { _ciWrapperStorage[ObjectIdentifier(self)] }
        set {
            if let newValue {
                _ciWrapperStorage[ObjectIdentifier(self)] = newValue
            } else {
                _ciWrapperStorage.removeValue(forKey: ObjectIdentifier(self))
            }
        }
    }

    /// Returns the shared CIFilterWrapper, creating it if needed.
    func ensureCIFilterWrapper() -> CIFilterWrapper {
        if let wrapper = _ciFilterWrapper { return wrapper }
        let wrapper = CIFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
        _ciFilterWrapper = wrapper
        return wrapper
    }
}

extension Sketch {
    /// Apply a CoreImage filter preset to an image.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - preset: The filter preset to apply.
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        context.ensureCIFilterWrapper().apply(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(
                width: CGFloat(image.width), height: CGFloat(image.height)
            )),
            to: image
        )
    }

    /// Apply a CoreImage filter to an image by name with custom parameters.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - name: The CIFilter name.
    ///   - parameters: The filter parameters.
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        context.ensureCIFilterWrapper().apply(filterName: name, parameters: parameters, to: image)
    }

    /// Generate an image using a CoreImage generator filter.
    ///
    /// - Parameters:
    ///   - preset: The generator filter preset.
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: The generated image, or `nil` if generation fails.
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        guard let tex = context.ensureCIFilterWrapper().generate(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(width: width, height: height)),
            width: width,
            height: height
        ) else { return nil }
        return MImage(texture: tex)
    }
}
