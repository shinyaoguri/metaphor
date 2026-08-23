import Foundation
import MetaphorCore
import MetaphorCoreImage

// MARK: - CoreImage フィルタブリッジ

/// Storage for the SketchContext-to-CIFilterWrapper mapping.
///
/// Keys are weak references to the SketchContext (pointer identity). Entries are
/// purged automatically even when a context is released without going through the
/// cleanup handler (SketchRunner's main path does not call `performCleanup()`), so
/// a wrapper holding a CIContext and a texture pool is never retained until process
/// exit, and a new context at a reused address never picks up someone else's stale
/// wrapper. A dictionary keyed by ObjectIdentifier would do both.
/// Same reason and same pattern as `_sketchContextStorage` in `Sketch.swift`.
@MainActor
private let _ciWrapperStorage = NSMapTable<AnyObject, CIFilterWrapper>(
    keyOptions: [.weakMemory, .objectPointerPersonality],
    valueOptions: .strongMemory
)

extension SketchContext {
    /// The lazily initialized CoreImage filter wrapper (external storage).
    var _ciFilterWrapper: CIFilterWrapper? {
        get { _ciWrapperStorage.object(forKey: self) }
        set {
            if let newValue {
                _ciWrapperStorage.setObject(newValue, forKey: self)
            } else {
                _ciWrapperStorage.removeObject(forKey: self)
            }
        }
    }

    /// Returns the shared CIFilterWrapper, creating it when needed.
    func ensureCIFilterWrapper() -> CIFilterWrapper {
        if let wrapper = _ciFilterWrapper { return wrapper }
        let wrapper = CIFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
        _ciFilterWrapper = wrapper
        addCleanupHandler { [weak self] in
            self?._ciFilterWrapper = nil
        }
        return wrapper
    }
}

extension Sketch {
    /// Applies a CoreImage filter preset to an image.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - preset: The filter preset to apply.
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        context.ensureCIFilterWrapper().apply(
            filterName: preset.filterName,
            parameters: preset.parameters(
                textureSize: CGSize(
                    width: CGFloat(image.width), height: CGFloat(image.height)
                )),
            to: image
        )
    }

    /// Applies a CoreImage filter to an image by name, with custom parameters.
    ///
    /// - Parameters:
    ///   - image: The image to filter.
    ///   - name: The CIFilter name.
    ///   - parameters: The filter parameters.
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        context.ensureCIFilterWrapper().apply(filterName: name, parameters: parameters, to: image)
    }

    /// Generates an image using a CoreImage generator filter.
    ///
    /// - Parameters:
    ///   - preset: The generator filter preset.
    ///   - width: The output image width, in pixels.
    ///   - height: The output image height, in pixels.
    /// - Returns: The generated image, or `nil` if generation fails.
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        guard
            let tex = context.ensureCIFilterWrapper().generate(
                filterName: preset.filterName,
                parameters: preset.parameters(textureSize: CGSize(width: width, height: height)),
                width: width,
                height: height
            )
        else { return nil }
        return MImage(texture: tex)
    }
}
